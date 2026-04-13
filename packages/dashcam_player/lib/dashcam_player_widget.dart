import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashcam_player_controller.dart';

/// Widget that displays the dashcam live stream using a native SurfaceView.
///
/// Uses Android PlatformView for direct surface rendering,
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

  @override
  void initState() {
    super.initState();
    _listenToErrors();
  }

  void _listenToErrors() {
    widget.controller.onError.listen((error) {
      if (mounted) {
        setState(() {
          _error = error;
          _isConnecting = false;
        });
      }
    });

    widget.controller.onStatusChanged.listen((status) {
      if (mounted && status == 'Playing') {
        setState(() {
          _isConnecting = false;
          _error = null;
        });
      }
    });
  }

  Future<void> _connect(int viewId) async {
    if (widget.controller.isDisposed) return;

    setState(() {
      _isConnecting = true;
      _error = null;
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Native SurfaceView via PlatformView
        if (defaultTargetPlatform == TargetPlatform.android)
          AndroidView(
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

        // Loading overlay
        if (_isConnecting)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Connecting to dashcam...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),

        // Error overlay
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
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
