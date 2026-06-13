import Foundation
import CoreVideo

private let TAG = "YoloDetector"
private let INPUT_SIZE = 320
private let NUM_CANDIDATES = 2100
private let NUM_CLASSES = 80
private let PERSON_CLASS = 0
private let TV_CLASS = 62
private let LAPTOP_CLASS = 63
private let CONFIDENCE_THRESHOLD: Float = 0.45
private let MONITOR_CONFIDENCE_THRESHOLD: Float = 0.30
private let NMS_IOU_THRESHOLD: Float = 0.45

private struct RawDetection {
    let classId: Int
    let confidence: Float
    let left: Float
    let top: Float
    let right: Float
    let bottom: Float
}

struct YoloResult {
    let personDetected: Bool
    let monitorDetected: Bool
    let personConfidence: Float?
    let monitorConfidence: Float?
}

/// YOLOv8n person/monitor detector. Port of the Kotlin `YoloDetector`, running the
/// same `yolov8n_float16.tflite` through the TensorFlow Lite C API.
///
/// This calls the C API (declared in `TFLiteCAPI.h`, imported via the bridging
/// header) instead of the `TensorFlowLiteSwift` pod: MediaPipeTasksVision already
/// statically links a full copy of the TFLite C API to run
/// `pose_landmarker_full.task`, and linking a second copy via TensorFlowLiteSwift
/// produces duplicate-symbol linker errors. Calling the C API directly binds to
/// the copy MediaPipe already provides.
///
/// Unlike Android (which receives a rotated YUV `Image` and de-rotates while
/// sampling), the iOS pipeline hands this an already-upright BGRA `CVPixelBuffer`,
/// so the input tensor is sampled directly with no rotation branches.
final class YoloDetector {

    private let model: OpaquePointer
    private let options: OpaquePointer
    private let interpreter: OpaquePointer

    init?() {
        guard let modelPath = Bundle.main.path(forResource: "yolov8n_float16", ofType: "tflite") else {
            NSLog("\(TAG): model yolov8n_float16.tflite not found in bundle")
            return nil
        }
        guard let model = TfLiteModelCreateFromFile(modelPath) else {
            NSLog("\(TAG): failed to load model")
            return nil
        }
        guard let options = TfLiteInterpreterOptionsCreate() else {
            TfLiteModelDelete(model)
            return nil
        }
        TfLiteInterpreterOptionsSetNumThreads(options, 4)
        guard let interpreter = TfLiteInterpreterCreate(model, options) else {
            TfLiteInterpreterOptionsDelete(options)
            TfLiteModelDelete(model)
            return nil
        }
        guard TfLiteInterpreterAllocateTensors(interpreter) == 0 else {
            NSLog("\(TAG): failed to allocate tensors")
            TfLiteInterpreterDelete(interpreter)
            TfLiteInterpreterOptionsDelete(options)
            TfLiteModelDelete(model)
            return nil
        }
        self.model = model
        self.options = options
        self.interpreter = interpreter
    }

    deinit {
        TfLiteInterpreterDelete(interpreter)
        TfLiteInterpreterOptionsDelete(options)
        TfLiteModelDelete(model)
    }

    func detect(pixelBuffer: CVPixelBuffer) -> YoloResult {
        let failResult = YoloResult(personDetected: false, monitorDetected: false,
                                     personConfidence: nil, monitorConfidence: nil)

        guard let inputTensor = TfLiteInterpreterGetInputTensor(interpreter, 0) else {
            return failResult
        }
        var input = buildInputTensor(pixelBuffer)
        let inputCopyStatus = input.withUnsafeMutableBufferPointer { buf in
            TfLiteTensorCopyFromBuffer(inputTensor, buf.baseAddress, buf.count * MemoryLayout<Float>.stride)
        }
        guard inputCopyStatus == 0, TfLiteInterpreterInvoke(interpreter) == 0,
              let outputTensor = TfLiteInterpreterGetOutputTensor(interpreter, 0) else {
            NSLog("\(TAG): inference failed")
            return failResult
        }

        let byteSize = TfLiteTensorByteSize(outputTensor)
        var floats = [Float](repeating: 0, count: byteSize / MemoryLayout<Float>.stride)
        let outputCopyStatus = floats.withUnsafeMutableBufferPointer { buf in
            TfLiteTensorCopyToBuffer(outputTensor, buf.baseAddress, byteSize)
        }
        guard outputCopyStatus == 0 else {
            NSLog("\(TAG): failed to read output tensor")
            return failResult
        }
        return buildResult(parseAndNms(floats))
    }

    // Samples the upright BGRA buffer into a [1,320,320,3] float tensor (RGB, 0–1).
    private func buildInputTensor(_ pb: CVPixelBuffer) -> [Float] {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        let outW = CVPixelBufferGetWidth(pb)
        let outH = CVPixelBufferGetHeight(pb)
        let rowStride = CVPixelBufferGetBytesPerRow(pb)
        guard let base = CVPixelBufferGetBaseAddress(pb) else {
            return [Float](repeating: 0, count: INPUT_SIZE * INPUT_SIZE * 3)
        }
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        var buf = [Float](repeating: 0, count: INPUT_SIZE * INPUT_SIZE * 3)
        var w = 0
        for oy in 0..<INPUT_SIZE {
            let sy = oy * outH / INPUT_SIZE
            for ox in 0..<INPUT_SIZE {
                let sx = ox * outW / INPUT_SIZE
                let p = sy * rowStride + sx * 4   // BGRA
                let b = Float(ptr[p + 0]) / 255
                let g = Float(ptr[p + 1]) / 255
                let r = Float(ptr[p + 2]) / 255
                buf[w + 0] = r
                buf[w + 1] = g
                buf[w + 2] = b
                w += 3
            }
        }
        return buf
    }

    private func parseAndNms(_ out: [Float]) -> [RawDetection] {
        // out is flat [1,84,2100]; value at logical [c][i] == out[c * NUM_CANDIDATES + i]
        var candidates: [RawDetection] = []
        candidates.reserveCapacity(64)
        for i in 0..<NUM_CANDIDATES {
            var bestId = 0
            var bestScore: Float = 0
            for c in 0..<NUM_CLASSES {
                let s = out[(4 + c) * NUM_CANDIDATES + i]
                if s > bestScore { bestScore = s; bestId = c }
            }
            let threshold = (bestId == TV_CLASS || bestId == LAPTOP_CLASS)
                ? MONITOR_CONFIDENCE_THRESHOLD : CONFIDENCE_THRESHOLD
            if bestScore < threshold { continue }

            let cx = out[0 * NUM_CANDIDATES + i]
            let cy = out[1 * NUM_CANDIDATES + i]
            let bw = out[2 * NUM_CANDIDATES + i]
            let bh = out[3 * NUM_CANDIDATES + i]
            candidates.append(RawDetection(
                classId: bestId,
                confidence: bestScore,
                left: clamp01((cx - bw / 2) / Float(INPUT_SIZE)),
                top: clamp01((cy - bh / 2) / Float(INPUT_SIZE)),
                right: clamp01((cx + bw / 2) / Float(INPUT_SIZE)),
                bottom: clamp01((cy + bh / 2) / Float(INPUT_SIZE))
            ))
        }
        return nms(candidates)
    }

    private func nms(_ candidates: [RawDetection]) -> [RawDetection] {
        let byClass = Dictionary(grouping: candidates, by: { $0.classId })
        var results: [RawDetection] = []
        for (_, group) in byClass {
            let sorted = group.sorted { $0.confidence > $1.confidence }
            var suppressed = [Bool](repeating: false, count: sorted.count)
            for i in sorted.indices {
                if suppressed[i] { continue }
                results.append(sorted[i])
                var j = i + 1
                while j < sorted.count {
                    if !suppressed[j] && iou(sorted[i], sorted[j]) > NMS_IOU_THRESHOLD {
                        suppressed[j] = true
                    }
                    j += 1
                }
            }
        }
        return results
    }

    private func iou(_ a: RawDetection, _ b: RawDetection) -> Float {
        let iL = max(a.left, b.left), iT = max(a.top, b.top)
        let iR = min(a.right, b.right), iB = min(a.bottom, b.bottom)
        if iR <= iL || iB <= iT { return 0 }
        let inter = (iR - iL) * (iB - iT)
        let aArea = (a.right - a.left) * (a.bottom - a.top)
        let bArea = (b.right - b.left) * (b.bottom - b.top)
        return inter / (aArea + bArea - inter)
    }

    private func buildResult(_ detections: [RawDetection]) -> YoloResult {
        var hasPerson = false, hasMonitor = false
        var personConf: Float?
        var monitorConf: Float?
        for d in detections {
            if d.classId == PERSON_CLASS {
                hasPerson = true
                if personConf == nil || d.confidence > personConf! { personConf = d.confidence }
            }
            if d.classId == TV_CLASS || d.classId == LAPTOP_CLASS {
                hasMonitor = true
                if monitorConf == nil || d.confidence > monitorConf! { monitorConf = d.confidence }
            }
        }
        return YoloResult(personDetected: hasPerson, monitorDetected: hasMonitor,
                          personConfidence: personConf, monitorConfidence: monitorConf)
    }

    private func clamp01(_ v: Float) -> Float { min(max(v, 0), 1) }
}
