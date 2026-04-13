import Flutter
import UIKit

public class DashcamPlayerPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dashcam_player", binaryMessenger: registrar.messenger())
        let instance = DashcamPlayerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "create":
            result(FlutterMethodNotImplemented)
        case "connect":
            result(FlutterMethodNotImplemented)
        case "disconnect":
            result(FlutterMethodNotImplemented)
        case "switchCamera":
            result(FlutterMethodNotImplemented)
        case "dispose":
            result(FlutterMethodNotImplemented)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
