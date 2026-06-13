#ifndef TFLiteCAPI_h
#define TFLiteCAPI_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Minimal subset of the TensorFlow Lite C API (tensorflow/lite/c/c_api.h),
// declared here so YoloDetector can call it directly.
//
// We deliberately do NOT add a `TensorFlowLiteSwift`/`TensorFlowLiteC` pod:
// MediaPipeTasksVision already statically links a full copy of this same C
// API (it uses it internally to run pose_landmarker_full.task), and linking
// a second copy causes ~48 duplicate-symbol linker errors for these exact
// functions. These declarations bind to that already-linked copy.
//
// `TfLiteStatus` (kTfLiteOk == 0) is ABI-compatible with int32_t, so status
// codes are returned as int32_t to avoid depending on the enum's Swift
// import representation — callers should check `== 0` for success.

typedef struct TfLiteModel TfLiteModel;
typedef struct TfLiteInterpreterOptions TfLiteInterpreterOptions;
typedef struct TfLiteInterpreter TfLiteInterpreter;
typedef struct TfLiteTensor TfLiteTensor;

extern TfLiteModel* TfLiteModelCreateFromFile(const char* model_path);
extern void TfLiteModelDelete(TfLiteModel* model);

extern TfLiteInterpreterOptions* TfLiteInterpreterOptionsCreate(void);
extern void TfLiteInterpreterOptionsDelete(TfLiteInterpreterOptions* options);
extern void TfLiteInterpreterOptionsSetNumThreads(TfLiteInterpreterOptions* options, int32_t num_threads);

extern TfLiteInterpreter* TfLiteInterpreterCreate(const TfLiteModel* model, const TfLiteInterpreterOptions* optional_options);
extern void TfLiteInterpreterDelete(TfLiteInterpreter* interpreter);
extern int32_t TfLiteInterpreterAllocateTensors(TfLiteInterpreter* interpreter);
extern int32_t TfLiteInterpreterInvoke(TfLiteInterpreter* interpreter);
extern TfLiteTensor* TfLiteInterpreterGetInputTensor(const TfLiteInterpreter* interpreter, int32_t input_index);
extern const TfLiteTensor* TfLiteInterpreterGetOutputTensor(const TfLiteInterpreter* interpreter, int32_t output_index);

extern int32_t TfLiteTensorCopyFromBuffer(TfLiteTensor* tensor, const void* input_data, size_t input_data_size);
extern int32_t TfLiteTensorCopyToBuffer(const TfLiteTensor* output_tensor, void* output_data, size_t output_data_size);
extern size_t TfLiteTensorByteSize(const TfLiteTensor* tensor);

#ifdef __cplusplus
}
#endif

#endif /* TFLiteCAPI_h */
