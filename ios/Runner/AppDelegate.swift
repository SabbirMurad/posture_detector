import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    private let channelName = "posture_detection"

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(name: channelName,
                                               binaryMessenger: controller.binaryMessenger)
            channel.setMethodCallHandler { [weak controller] call, result in
                switch call.method {
                case "startDetection":
                    guard let controller = controller else {
                        result(nil)
                        return
                    }
                    let answers = call.arguments as? [String: Any]
                    let mods = RosaScorer.WorkstationModifiers.fromMap(answers)
                    let vc = PoseDetectionViewController(workstationModifiers: mods)
                    vc.onComplete = { detectionResult in
                        // detectionResult is nil on cancel, else
                        // ["photo_paths": [String], "rosa_scores": [[String: Any]]]
                        result(detectionResult)
                    }
                    controller.present(vc, animated: true)
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
