import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/rtsp_service.dart';

/// Live streaming screen for the dashcam RTSP feed
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
  late final RtspService _rtspService;
  VideoController? _videoController;

  int _selectedCameraIndex = 0;
  RtspTransport _selectedTransport = RtspTransport.udp;
  bool _isLoading = false;
  bool _showDebugLog = false;
  bool _isTakingSnapshot = false;
  bool _showFlash = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _rtspService = RtspService(rtspUrl: widget.rtspUrl);
    // Set initial transport from config
    _selectedTransport = _rtspService.transport;
    _connectToStream();
  }

  @override
  void dispose() {
    _rtspService.dispose();
    super.dispose();
  }

  Future<void> _connectToStream({bool skipPrerequisites = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _showDebugLog = false; // Hide debug log on new connection attempt
    });

    try {
      // Set transport before connecting
      _rtspService.setTransport(_selectedTransport);

      await _rtspService.connect(
        cameraIndex: _selectedCameraIndex,
        skipPrerequisites: skipPrerequisites,
      );
      // Create video controller with the player
      if (_rtspService.player != null && mounted) {
        _videoController = VideoController(_rtspService.player!);

        // Enable stream quality monitoring
        _rtspService.monitorStreamQuality(
          onBufferingDetected: () {
            if (mounted) {
              setState(() {
                _showDebugLog = true;
              });
            }
          },
          onTransportSwitchRecommended: (recommendedTransport) {
            if (mounted && _selectedTransport != recommendedTransport) {
              // Could show a snackbar or dialog here
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Buffering detected. Consider switching to ${recommendedTransport.description} transport.',
                  ),
                  action: SnackBarAction(
                    label: 'SWITCH',
                    onPressed: () => _switchTransport(recommendedTransport),
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          },
        );

        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
          _showDebugLog = true; // Show debug log on error
        });
      }
    }
  }

  Future<void> _switchTransport(RtspTransport transport) async {
    if (_selectedTransport == transport) return;

    setState(() {
      _selectedTransport = transport;
    });

    // Reconnect with new transport
    await _reconnect(skipPrerequisites: false);
  }

  Future<void> _switchCamera(int index) async {
    if (_selectedCameraIndex == index) return;

    setState(() {
      _selectedCameraIndex = index;
      _isLoading = true;
      _errorMessage = null;
      _showDebugLog = false;
    });

    try {
      await _rtspService.switchCamera(index);
      // Recreate video controller with the player
      if (_rtspService.player != null && mounted) {
        _videoController = VideoController(_rtspService.player!);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
          _showDebugLog = true;
        });
      }
    }
  }

  Future<void> _reconnect({bool skipPrerequisites = false}) async {
    await _connectToStream(skipPrerequisites: skipPrerequisites);
  }

  /// Take a snapshot using the dashcam's snapshot API
  Future<void> _takeSnapshot() async {
    if (_isTakingSnapshot) return; // Prevent double-tap

    // Trigger flash animation
    setState(() {
      _isTakingSnapshot = true;
      _showFlash = true;
    });

    try {
      final photoPath = await _rtspService.takeSnapshot();

      // Hide flash after delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _showFlash = false;
          });
        }
      });

      if (mounted) {
        if (photoPath.isNotEmpty) {
          // Snapshot successful with path
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
              action: SnackBarAction(
                label: 'VIEW',
                textColor: Colors.white,
                onPressed: () {
                  // TODO: Navigate to photo viewer
                },
              ),
            ),
          );
        } else if (photoPath == '') {
          // Snapshot successful but path not found (API worked but file list query failed)
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
        } else {
          // Snapshot failed
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Snapshot failed: ${_rtspService.errorMessage ?? "Unknown error"}'),
                  ),
                ],
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
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

  Color _getStatusColor() {
    switch (_rtspService.status) {
      case StreamConnectionStatus.connected:
        return Colors.green;
      case StreamConnectionStatus.connecting:
        return Colors.orange;
      case StreamConnectionStatus.error:
        return Colors.red;
      case StreamConnectionStatus.disconnected:
        return Colors.grey;
    }
  }

  String _getStatusText() {
    switch (_rtspService.status) {
      case StreamConnectionStatus.connected:
        return 'Connected';
      case StreamConnectionStatus.connecting:
        return 'Connecting...';
      case StreamConnectionStatus.error:
        return 'Error';
      case StreamConnectionStatus.disconnected:
        return 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionLog = _rtspService.connectionLog;
    final serviceErrorMessage = _rtspService.errorMessage;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Dashcam Live'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // Transport protocol selection
          PopupMenuButton<RtspTransport>(
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _selectedTransport == RtspTransport.udp
                      ? Icons.speed
                      : Icons.wifi_protected_setup,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  _selectedTransport.value.toUpperCase(),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            onSelected: (transport) {
              _switchTransport(transport);
            },
            tooltip: 'Transport protocol',
            itemBuilder: (context) => [
              PopupMenuItem(
                value: RtspTransport.udp,
                child: Row(
                  children: [
                    Icon(
                      Icons.speed,
                      color: _selectedTransport == RtspTransport.udp
                          ? Colors.blue
                          : Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('UDP (Low Latency)'),
                        Text(
                          'Lower latency, accepts packet loss',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: RtspTransport.tcp,
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_protected_setup,
                      color: _selectedTransport == RtspTransport.tcp
                          ? Colors.blue
                          : Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('TCP (Reliable)'),
                        Text(
                          'Higher latency, error-free',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Debug log toggle
          IconButton(
            icon: Icon(_showDebugLog ? Icons.bug_report : Icons.bug_report_outlined),
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
                // Video widget
                Center(
                  child: _isLoading || _rtspService.player == null || _videoController == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Connecting to dashcam...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        )
                      : Video(
                          controller: _videoController!,
                          controls: NoVideoControls,
                        ),
                ),
                // Error message overlay
                if (_errorMessage != null)
                  Container(
                    color: Colors.black87,
                    child: Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Connection Error',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (serviceErrorMessage != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    serviceErrorMessage,
                                    style: const TextStyle(color: Colors.orange),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () => _reconnect(skipPrerequisites: false),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Reconnect'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade700,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _reconnect(skipPrerequisites: true),
                                    icon: const Icon(Icons.skip_next),
                                    label: const Text('Skip HTTP Check'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange.shade700,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // Stream info overlay (when connected)
                if (_rtspService.status == StreamConnectionStatus.connected &&
                    _errorMessage == null)
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
                          const SizedBox(width: 8),
                          Icon(
                            _selectedTransport == RtspTransport.udp
                                ? Icons.speed
                                : Icons.wifi_protected_setup,
                            color: _selectedTransport == RtspTransport.udp
                                ? Colors.green.shade400
                                : Colors.orange.shade400,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _selectedTransport.value.toUpperCase(),
                            style: TextStyle(
                              color: _selectedTransport == RtspTransport.udp
                                  ? Colors.green.shade400
                                  : Colors.orange.shade400,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Flash overlay for snapshot feedback
                if (_showFlash)
                  Container(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                // Debug log overlay
                if (_showDebugLog && connectionLog.isNotEmpty)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade700),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.code, size: 16, color: Colors.white70),
                                const SizedBox(width: 8),
                                const Text(
                                  'Connection Log',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
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
                                  connectionLog.join('\n'),
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
                OutlinedButton.icon(
                  onPressed: () => _reconnect(skipPrerequisites: false),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reconnect'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _rtspService.status == StreamConnectionStatus.connected
          ? FloatingActionButton.extended(
              onPressed: _isTakingSnapshot ? null : _takeSnapshot,
              icon: _isTakingSnapshot
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
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
}
