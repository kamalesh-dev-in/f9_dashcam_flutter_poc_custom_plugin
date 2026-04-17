import 'package:flutter/material.dart';
import 'package:dashcam_player/dashcam_player.dart';
import '../services/rtsp_service.dart';

/// Live streaming screen for the dashcam RTSP feed.
///
/// Uses the native FFmpeg plugin (dashcam_player) for low-latency streaming
/// via Android PlatformView with direct SurfaceView rendering.
class LiveStreamScreen extends StatefulWidget {
  final String rtspUrl;

  const LiveStreamScreen({
    super.key,
    this.rtspUrl = RtspConfig.defaultRtspUrl,
  });

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  DashcamPlayerController? _dashcamController;
  RtspService? _rtspService; // Kept for HTTP APIs (snapshot, file list, etc.)

  int _selectedCameraIndex = 0;
  bool _isLoading = false;
  bool _showDebugLog = false;
  bool _isTakingSnapshot = false;
  bool _showFlash = false;
  String? _errorMessage;
  int? _latencyMs;

  final List<String> _debugLog = [];

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    _dashcamController = DashcamPlayerController();

    // Listen to events
    _dashcamController!.onStatusChanged.listen((status) {
      _addLog('[Status] $status');
      if (status == 'Playing' && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      }
    });

    _dashcamController!.onError.listen((error) {
      _addLog('[Error] $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = error;
          _showDebugLog = true;
        });
      }
    });

    _dashcamController!.onLatencyMeasured.listen((latency) {
      _addLog('[Latency] ${latency}ms');
      if (mounted) {
        setState(() {
          _latencyMs = latency;
        });
      }
    });

    // RTSP service for HTTP-only APIs (snapshot, file list)
    _rtspService = RtspService(rtspUrl: widget.rtspUrl);
  }

  void _addLog(String message) {
    _debugLog.add(message);
    if (_debugLog.length > 100) {
      _debugLog.removeAt(0);
    }
  }

  @override
  void dispose() {
    _dashcamController?.dispose();
    _rtspService?.dispose();
    super.dispose();
  }

  Future<void> _reconnect() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _latencyMs = null;
      _showDebugLog = false;
    });

    // Dispose old controller and create new one
    await _dashcamController?.dispose();
    _initPlayer();
    setState(() {});
  }

  Future<void> _switchCamera(int index) async {
    if (_selectedCameraIndex == index) return;

    setState(() {
      _selectedCameraIndex = index;
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await _dashcamController?.switchCamera(index) ?? false;
      if (mounted) {
        setState(() {
          _isLoading = !success;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// Take a snapshot using the dashcam's snapshot API
  Future<void> _takeSnapshot() async {
    if (_isTakingSnapshot) return;

    setState(() {
      _isTakingSnapshot = true;
      _showFlash = true;
    });

    try {
      final photoPath = await _rtspService?.takeSnapshot() ?? '';

      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _showFlash = false;
          });
        }
      });

      if (mounted) {
        if (photoPath.isNotEmpty) {
          final fileName = photoPath.split('/').last;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Snapshot saved: $fileName')),
                ],
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('Snapshot saved to /photo/ folder')),
                ],
              ),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Snapshot error: $e')),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTakingSnapshot = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Dashcam Live'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // Debug log toggle
          IconButton(
            icon: Icon(
                _showDebugLog ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () {
              setState(() {
                _showDebugLog = !_showDebugLog;
              });
            },
            tooltip: 'Toggle debug log',
          ),
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _getStatusColor(),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getStatusText(),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Video player
          Expanded(
            child: Stack(
              children: [
                // Native FFmpeg player via PlatformView
                if (_dashcamController != null)
                  DashcamPlayerWidget(
                    controller: _dashcamController!,
                    cameraIndex: _selectedCameraIndex,
                  )
                else
                  const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),

                // Flash overlay for snapshot feedback
                if (_showFlash)
                  Container(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),

                // Stream info overlay (when connected)
                if (_latencyMs != null)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.speed,
                            color: Colors.greenAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_latencyMs}ms',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.hd,
                            color: Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${RtspConfig.width}x${RtspConfig.height}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.fiber_manual_record,
                            color: Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${RtspConfig.fps} FPS',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Debug log overlay
                if (_showDebugLog && _debugLog.isNotEmpty)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      constraints:
                          const BoxConstraints(maxWidth: 400, maxHeight: 300),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade700),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.code,
                                    size: 16, color: Colors.white70),
                                const SizedBox(width: 8),
                                const Text(
                                  'Connection Log',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  color: Colors.white70,
                                  onPressed: () {
                                    setState(() {
                                      _showDebugLog = false;
                                    });
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: SingleChildScrollView(
                                child: Text(
                                  _debugLog.join('\n'),
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Camera selector controls
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Camera Selection',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: List.generate(
                    RtspConfig.cameraNames.length,
                    (index) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: index < RtspConfig.cameraNames.length - 1
                              ? 8
                              : 0,
                        ),
                        child: ElevatedButton(
                          onPressed: () => _switchCamera(index),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selectedCameraIndex == index
                                ? Colors.blue.shade700
                                : Colors.grey.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(RtspConfig.cameraNames[index]),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Reconnect button
                // OutlinedButton.icon(
                //   onPressed: _reconnect,
                //   icon: const Icon(Icons.refresh, size: 18),
                //   label: const Text('Reconnect'),
                //   style: OutlinedButton.styleFrom(
                //     foregroundColor: Colors.white70,
                //     side: BorderSide(color: Colors.grey.shade700),
                //   ),
                // ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _latencyMs != null
          ? FloatingActionButton.extended(
              onPressed: _isTakingSnapshot ? null : _takeSnapshot,
              icon: _isTakingSnapshot
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.black),
                      ),
                    )
                  : const Icon(Icons.camera_alt),
              label: Text(_isTakingSnapshot ? 'Capturing...' : 'Snapshot'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            )
          : null,
    );
  }

  Color _getStatusColor() {
    if (_latencyMs != null) return Colors.green;
    if (_isLoading) return Colors.orange;
    if (_errorMessage != null) return Colors.red;
    return Colors.grey;
  }

  String _getStatusText() {
    if (_latencyMs != null) return 'Connected';
    if (_isLoading) return 'Connecting...';
    if (_errorMessage != null) return 'Error';
    return 'Disconnected';
  }
}
