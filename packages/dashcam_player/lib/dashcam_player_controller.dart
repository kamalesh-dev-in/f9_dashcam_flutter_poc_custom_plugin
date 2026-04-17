import 'dart:async';
import 'package:flutter/services.dart';
import 'dashcam_config.dart';

/// Controller for the dashcam native FFmpeg player.
///
/// Communicates with the native Android plugin via MethodChannel
/// and receives streaming events via EventChannel.
class DashcamPlayerController {
  static const MethodChannel _channel = MethodChannel('dashcam_player');
  static const EventChannel _eventChannel =
      EventChannel('dashcam_player/events');

  int? _playerId;
  bool _isDisposed = false;
  final DashcamConfig _config;

  // Stream controllers for public API
  final _statusController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _latencyController = StreamController<int>.broadcast();
  final _preparedController = StreamController<void>.broadcast();

  /// Status change events (e.g. "Connecting...", "Playing")
  Stream<String> get onStatusChanged => _statusController.stream;

  /// Error events
  Stream<String> get onError => _errorController.stream;

  /// Latency measurement in milliseconds when video starts rendering
  Stream<int> get onLatencyMeasured => _latencyController.stream;

  /// Fired when player is prepared and ready
  Stream<void> get onPrepared => _preparedController.stream;

  /// Whether the controller has been disposed
  bool get isDisposed => _isDisposed;

  /// The effective config being used (overrides + F9 defaults)
  DashcamConfig get config => _config;

  DashcamPlayerController({DashcamConfig? config})
      : _config = config ?? const DashcamConfig() {
    _listenToEvents();
  }

  void _listenToEvents() {
    _eventChannel.receiveBroadcastStream().listen(
      (event) {
        final map = event as Map;
        final type = map['type'] as String;
        final data = map['data'] as Map? ?? {};
        switch (type) {
          case 'statusChanged':
            _statusController.add(data['message'] as String? ?? '');
          case 'error':
            _errorController.add(data['message'] as String? ?? 'Unknown error');
          case 'videoRenderingStarted':
            _latencyController.add(data['latencyMs'] as int? ?? 0);
          case 'prepared':
            _preparedController.add(null);
        }
      },
      onError: (error) {
        _errorController.add(error.toString());
      },
    );
  }

  /// Create the native player associated with a PlatformView.
  /// Must be called after the PlatformView is created (onPlatformViewCreated).
  Future<int> create(int viewId) async {
    _playerId = await _channel.invokeMethod<int>('create', {
      'viewId': viewId,
      'config': _config.toMap(),
    });
    return _playerId!;
  }

  /// Connect to the dashcam RTSP stream.
  /// [cameraIndex]: 0=Front, 1=Rear, 2=PiP
  Future<bool> connect({int cameraIndex = 0}) async {
    if (_playerId == null) {
      throw StateError('Player not created. Call create() first.');
    }
    return await _channel.invokeMethod<bool>('connect', {
      'playerId': _playerId,
      'cameraIndex': cameraIndex,
    }) ?? false;
  }

  /// Disconnect from the stream (stop playback).
  Future<void> disconnect() async {
    if (_playerId == null) return;
    await _channel.invokeMethod<void>('disconnect', {
      'playerId': _playerId,
    });
  }

  /// Reconnect to the dashcam. Disconnects current stream and starts fresh.
  Future<bool> reconnect({int cameraIndex = 0}) async {
    if (_playerId == null || _isDisposed) return false;
    await disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
    return await connect(cameraIndex: cameraIndex);
  }

  /// Switch camera on the dashcam.
  /// [cameraIndex]: 0=Front, 1=Rear, 2=PiP
  Future<bool> switchCamera(int cameraIndex) async {
    if (_playerId == null) {
      throw StateError('Player not created. Call create() first.');
    }
    return await _channel.invokeMethod<bool>('switchCamera', {
      'playerId': _playerId,
      'cameraIndex': cameraIndex,
    }) ?? false;
  }

  /// Release all native resources.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    if (_playerId != null) {
      try {
        await _channel.invokeMethod<void>('dispose', {
          'playerId': _playerId,
        });
      } catch (_) {
        // Ignore errors during dispose
      }
    }

    await _statusController.close();
    await _errorController.close();
    await _latencyController.close();
    await _preparedController.close();
  }
}
