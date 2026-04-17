package com.dashcam.player

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Flutter plugin entry point for dashcam_player.
 *
 * Registers:
 * - MethodChannel "dashcam_player" for player commands
 * - EventChannel "dashcam_player/events" for status/error/latency events
 * - PlatformView "dashcam_player_view" for native SurfaceView rendering
 */
class DashcamPlayerPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Registry of active players keyed by player ID */
    private val playerRegistry = mutableMapOf<Int, DashcamNativePlayer>()
    private var nextPlayerId = 1

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Method channel for commands
        channel = MethodChannel(binding.binaryMessenger, "dashcam_player")
        channel.setMethodCallHandler(this)

        // Event channel for streaming events
        eventChannel = EventChannel(binding.binaryMessenger, "dashcam_player/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                eventSink = sink
            }
            override fun onCancel(args: Any?) {
                eventSink = null
            }
        })

        // Register PlatformView for native SurfaceView rendering
        binding.platformViewRegistry.registerViewFactory(
            "dashcam_player_view",
            DashcamPlatformViewFactory()
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        playerRegistry.values.forEach { it.release() }
        playerRegistry.clear()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "create" -> handleCreate(call, result)
            "connect" -> handleConnect(call, result)
            "disconnect" -> handleDisconnect(call, result)
            "switchCamera" -> handleSwitchCamera(call, result)
            "dispose" -> handleDispose(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Create a new player instance associated with a PlatformView.
     * Args: { "viewId": int }
     * Returns: playerId (int)
     */
    private fun handleCreate(call: MethodCall, result: Result) {
        val viewId = call.argument<Int>("viewId")
        if (viewId == null) {
            result.error("INVALID_ARGS", "viewId is required", null)
            return
        }

        val platformView = DashcamPlatformView.get(viewId)
        if (platformView == null) {
            result.error("VIEW_NOT_FOUND", "PlatformView not found for viewId: $viewId", null)
            return
        }

        // Extract optional config map from Dart
        @Suppress("UNCHECKED_CAST")
        val configMap = call.argument<Map<String, Any>>("config")
        val config = DashcamConfig(configMap)

        val playerId = nextPlayerId++
        val player = DashcamNativePlayer(playerId, this, config)
        player.setSurfaceView(platformView.getSurfaceView())
        playerRegistry[playerId] = player

        result.success(playerId)
    }

    /**
     * Connect to dashcam RTSP stream.
     * Args: { "playerId": int, "rtspUrl": String (unused, uses config), "cameraIndex": int }
     * Returns: bool success
     */
    private fun handleConnect(call: MethodCall, result: Result) {
        val playerId = call.argument<Int>("playerId") ?: run {
            result.error("INVALID_ARGS", "playerId is required", null)
            return
        }
        val cameraIndex = call.argument<Int>("cameraIndex") ?: 0

        val player = playerRegistry[playerId]
        if (player == null) {
            result.error("PLAYER_NOT_FOUND", "No player for id: $playerId", null)
            return
        }

        // Run connect on IO thread, return result on main thread
        CoroutineScope(Dispatchers.IO).launch {
            val success = player.connect(cameraIndex)
            mainHandler.post { result.success(success) }
        }
    }

    /**
     * Disconnect from stream (stop playback).
     * Args: { "playerId": int }
     */
    private fun handleDisconnect(call: MethodCall, result: Result) {
        val playerId = call.argument<Int>("playerId") ?: run {
            result.error("INVALID_ARGS", "playerId is required", null)
            return
        }

        val player = playerRegistry[playerId]
        player?.stop()
        result.success(null)
    }

    /**
     * Switch camera on the dashcam.
     * Args: { "playerId": int, "cameraIndex": int }
     * Returns: bool success
     */
    private fun handleSwitchCamera(call: MethodCall, result: Result) {
        val playerId = call.argument<Int>("playerId") ?: run {
            result.error("INVALID_ARGS", "playerId is required", null)
            return
        }
        val cameraIndex = call.argument<Int>("cameraIndex") ?: 0

        val player = playerRegistry[playerId]
        if (player == null) {
            result.error("PLAYER_NOT_FOUND", "No player for id: $playerId", null)
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            val success = player.switchCamera(cameraIndex)
            mainHandler.post { result.success(success) }
        }
    }

    /**
     * Dispose player and release resources.
     * Args: { "playerId": int }
     */
    private fun handleDispose(call: MethodCall, result: Result) {
        val playerId = call.argument<Int>("playerId") ?: run {
            result.error("INVALID_ARGS", "playerId is required", null)
            return
        }

        val player = playerRegistry.remove(playerId)
        player?.release()
        result.success(null)
    }

    /**
     * Send an event to Flutter via EventChannel.
     * Must be called on the main thread.
     */
    fun sendEvent(type: String, data: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(mapOf("type" to type, "data" to data))
        }
    }
}
