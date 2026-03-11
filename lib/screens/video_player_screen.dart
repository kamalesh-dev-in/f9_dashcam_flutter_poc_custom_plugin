import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/f9_file.dart';
import '../services/rtsp_service.dart';

/// Video player screen for playing back recorded videos from the dashcam
class VideoPlayerScreen extends StatefulWidget {
  final F9File file;

  const VideoPlayerScreen({
    super.key,
    required this.file,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final RtspService _rtspService;
  Player? _player;
  VideoController? _videoController;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _rtspService = RtspService();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      // Enter playback mode
      final entered = await _rtspService.enterPlaybackMode();
      if (!entered) {
        throw Exception('Failed to enter playback mode');
      }

      // Build RTSP URL
      final rtspUrl = _rtspService.buildPlaybackRtspUrl(widget.file.rtspPath);
      developer.log('[VideoPlayer] Playing: $rtspUrl', name: 'dashcam.video');

      // Create player
      _player = Player();

      _player!.stream.position.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });

      _player!.stream.duration.listen((duration) {
        if (mounted) {
          setState(() {
            _duration = duration;
          });
        }
      });

      _player!.stream.error.listen((error) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = error.toString();
          });
        }
      });

      await _player!.open(Media(rtspUrl), play: true);

      if (mounted) {
        _videoController = VideoController(_player!);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _rtspService.exitPlaybackMode();
    _player?.dispose();
    _rtspService.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    await _initializePlayer();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Video Playback'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: _isLoading || _videoController == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Loading video...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        )
                      : _hasError
                          ? _buildErrorWidget()
                          : Video(
                              controller: _videoController!,
                              controls: MaterialVideoControls,
                            ),
                ),
                if (!_isLoading && !_hasError)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: _buildFileInfoOverlay(),
                  ),
              ],
            ),
          ),
          if (!_isLoading && !_hasError)
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.file.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _buildInfoChip(
                        icon: Icons.calendar_today,
                        label: widget.file.dateString,
                      ),
                      _buildInfoChip(
                        icon: Icons.storage,
                        label: widget.file.sizeString,
                      ),
                      if (widget.file.duration > 0)
                        _buildInfoChip(
                          icon: Icons.access_time,
                          label: widget.file.durationString,
                        ),
                      if (widget.file.hasGps)
                        _buildInfoChip(
                          icon: Icons.gps_fixed,
                          label: 'GPS',
                          iconColor: Colors.lightGreen,
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileInfoOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_circle_outline,
            color: Colors.white70,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            _formatDuration(_position),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          if (_duration > Duration.zero) ...[
            const SizedBox(width: 4),
            Text(
              '/ ${_formatDuration(_duration)}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    Color? iconColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: iconColor ?? Colors.white70,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Container(
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
                  'Playback Error',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (_errorMessage != null)
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
