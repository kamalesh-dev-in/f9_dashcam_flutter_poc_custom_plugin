import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/f9_file.dart';
import '../services/rtsp_service.dart';

/// Reusable thumbnail widget for displaying file thumbnails
class FileThumbnail extends StatefulWidget {
  final F9File file;
  final double size;
  final double borderRadius;
  final bool showGpsIndicator;

  const FileThumbnail({
    super.key,
    required this.file,
    this.size = 80,
    this.borderRadius = 4,
    this.showGpsIndicator = true,
  });

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  final RtspService _rtspService = RtspService();
  ImageProvider? _imageProvider;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final bytes = await _rtspService.getThumbnail(widget.file.httpPath);
      if (mounted) {
        setState(() {
          _imageProvider = MemoryImage(bytes);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _rtspService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: _buildThumbnailContent(),
          ),
          Positioned(
            bottom: 2,
            left: 2,
            child: _buildTypeIndicator(),
          ),
          if (widget.showGpsIndicator && widget.file.hasGps)
            Positioned(
              top: 2,
              left: 2,
              child: _buildGpsIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildThumbnailContent() {
    if (_isLoading) {
      return Container(
        color: Colors.grey.shade800,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
            ),
          ),
        ),
      );
    }

    if (_hasError || _imageProvider == null) {
      return Container(
        color: Colors.grey.shade800,
        child: Icon(
          widget.file.type == FileType.video
              ? Icons.videocam_outlined
              : Icons.image_outlined,
          color: Colors.white54,
          size: widget.size * 0.4,
        ),
      );
    }

    return Image(
      image: _imageProvider!,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey.shade800,
          child: Icon(
            widget.file.type == FileType.video
                ? Icons.videocam_outlined
                : Icons.image_outlined,
            color: Colors.white54,
            size: widget.size * 0.4,
          ),
        );
      },
    );
  }

  Widget _buildTypeIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.file.type == FileType.video ? Icons.play_arrow : Icons.image,
            color: Colors.white,
            size: 12,
          ),
          if (widget.file.type == FileType.video && widget.file.duration > 0)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                widget.file.durationString,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGpsIndicator() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.gps_fixed,
        color: Colors.lightGreen,
        size: 12,
      ),
    );
  }
}
