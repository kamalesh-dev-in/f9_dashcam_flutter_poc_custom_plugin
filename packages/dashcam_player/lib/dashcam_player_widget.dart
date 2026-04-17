import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashcam_player_controller.dart';

/// Widget that displays the dashcam live stream using a native SurfaceView.
///
/// Uses PlatformView for direct surface rendering,
/// bypassing Flutter's rendering pipeline for minimal latency.
class DashcamPlayerWidget extends StatefulWidget {
  final DashcamPlayerController controller;
  final int cameraIndex;

  const DashcamPlayerWidget({
    super.key,
    required this.controller,
    this.cameraIndex = 0,
  });

  @override
  State<DashcamPlayerWidget> createState() => _DashcamPlayerWidgetState();
}

class _DashcamPlayerWidgetState extends State<DashcamPlayerWidget> {
  bool _isConnecting = false;
  String? _error;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _listenToEvents();
  }

  void _listenToEvents() {
    widget.controller.onError.listen((error) {
      if (mounted) {
        setState(() {
          _error = error;
          _isConnecting = false;
          _statusMessage = null;
        });
      }
    });

    widget.controller.onStatusChanged.listen((status) {
      if (mounted) {
        setState(() {
          _statusMessage = status;
          if (status == 'Playing') {
            _isConnecting = false;
            _error = null;
            _statusMessage = null;
          }
        });
      }
    });
  }

  Future<void> _connect(int viewId) async {
    if (widget.controller.isDisposed) return;

    setState(() {
      _isConnecting = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      await widget.controller.create(viewId);
      final success = await widget.controller.connect(
        cameraIndex: widget.cameraIndex,
      );
      if (!success && mounted) {
        setState(() {
          _error = 'Connection failed';
          _isConnecting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _reconnect() async {
    if (widget.controller.isDisposed) return;

    setState(() {
      _isConnecting = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      final success = await widget.controller.reconnect(
        cameraIndex: widget.cameraIndex,
      );
      if (!success && mounted) {
        setState(() {
          _error = 'Connection failed';
          _isConnecting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isConnecting = false;
        });
      }
    }
  }

  void _cancelConnection() {
    widget.controller.disconnect();
    setState(() {
      _isConnecting = false;
      _error = 'Connection cancelled';
      _statusMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Native view via PlatformView (Android: SurfaceView, iOS: MTKView)
        if (defaultTargetPlatform == TargetPlatform.android)
          AndroidView(
            viewType: 'dashcam_player_view',
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _connect,
          )
        else if (defaultTargetPlatform == TargetPlatform.iOS)
          UiKitView(
            viewType: 'dashcam_player_view',
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _connect,
          )
        else
          const Center(
            child: Text(
              'Platform not supported yet',
              style: TextStyle(color: Colors.white),
            ),
          ),

        // Loading overlay with status and cancel
        if (_isConnecting)
          Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage ?? 'Connecting to dashcam...',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _cancelConnection,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Error overlay with reconnect button
        if (_error != null && !_isConnecting)
          Container(
            color: Colors.black87,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _reconnect,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reconnect'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
