import Flutter
import UIKit

/// Flutter plugin entry point for dashcam_player on iOS.
///
/// Registers:
/// - MethodChannel "dashcam_player" for player commands
/// - EventChannel "dashcam_player/events" for status/error/latency events
/// - PlatformView "dashcam_player_view" for native MTKView rendering
public class DashcamPlayerPlugin: NSObject, FlutterPlugin {

    private var channel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    fileprivate var eventSink: FlutterEventSink?

    /// Registry of active players keyed by player ID
    private var playerRegistry: [Int: DashcamNativePlayer] = [:]
    private var nextPlayerId = 1

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dashcam_player", binaryMessenger: registrar.messenger())
        let instance = DashcamPlayerPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Event channel for streaming events
        let eventChannel = FlutterEventChannel(name: "dashcam_player/events", binaryMessenger: registrar.messenger())
        instance.eventChannel = eventChannel
        eventChannel.setStreamHandler(StreamHandlerFactory(plugin: instance))

        // Register PlatformView for native MTKView rendering
        let factory = DashcamPlatformViewFactory()
        registrar.register(factory, withId: "dashcam_player_view")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "create":
            handleCreate(call, result: result)
        case "connect":
            handleConnect(call, result: result)
        case "disconnect":
            handleDisconnect(call, result: result)
        case "switchCamera":
            handleSwitchCamera(call, result: result)
        case "dispose":
            handleDispose(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Method Handlers

    private func handleCreate(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let viewId = args["viewId"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "viewId is required", details: nil))
            return
        }

        guard let platformView = DashcamPlatformView.get(Int64(viewId)) else {
            result(FlutterError(code: "VIEW_NOT_FOUND", message: "PlatformView not found for viewId: \(viewId)", details: nil))
            return
        }

        // Extract optional config dictionary from Dart
        let configDict = args["config"] as? [String: Any]
        let config = DashcamConfig(dict: configDict)

        let playerId = nextPlayerId
        nextPlayerId += 1

        let player = DashcamNativePlayer(playerId: playerId, plugin: self, config: config)
        player.setMetalView(platformView.getMetalView(), platformView: platformView)
        playerRegistry[playerId] = player

        result(playerId)
    }

    private func handleConnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "playerId is required", details: nil))
            return
        }
        let cameraIndex = args["cameraIndex"] as? Int ?? 0

        guard let player = playerRegistry[playerId] else {
            result(FlutterError(code: "PLAYER_NOT_FOUND", message: "No player for id: \(playerId)", details: nil))
            return
        }

        player.connect(cameraIndex: cameraIndex) { success in
            result(success)
        }
    }

    private func handleDisconnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "playerId is required", details: nil))
            return
        }

        playerRegistry[playerId]?.stop()
        result(nil)
    }

    private func handleSwitchCamera(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "playerId is required", details: nil))
            return
        }
        let cameraIndex = args["cameraIndex"] as? Int ?? 0

        guard let player = playerRegistry[playerId] else {
            result(FlutterError(code: "PLAYER_NOT_FOUND", message: "No player for id: \(playerId)", details: nil))
            return
        }

        player.switchCamera(camera: cameraIndex) { success in
            result(success)
        }
    }

    private func handleDispose(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let playerId = args["playerId"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "playerId is required", details: nil))
            return
        }

        let player = playerRegistry.removeValue(forKey: playerId)
        player?.release()
        result(nil)
    }

    // MARK: - Event Channel

    /// Send an event to Flutter via EventChannel.
    func sendEvent(_ type: String, data: [String: Any]) {
        eventSink?(["type": type, "data": data])
    }
}

// MARK: - Stream Handler

private class StreamHandlerFactory: NSObject, FlutterStreamHandler {
    private weak var plugin: DashcamPlayerPlugin?

    init(plugin: DashcamPlayerPlugin) {
        self.plugin = plugin
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.eventSink = nil
        return nil
    }
}
