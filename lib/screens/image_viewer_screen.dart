import 'package:flutter/material.dart';
import '../models/f9_file.dart';

/// Screen for viewing a single image with zoom/pan support
class ImageViewerScreen extends StatefulWidget {
  final F9File file;

  const ImageViewerScreen({
    super.key,
    required this.file,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  final TransformationController _transformationController =
      TransformationController();
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(() {
      setState(() {}); // Rebuild to show/hide zoom controls
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  String _getImageUrl() {
    // The file path from API is like /mnt/card/image_front/XXX.jpg
    // The full URL is http://192.168.169.1/mnt/card/image_front/XXX.jpg
    return 'http://192.168.169.1${widget.file.name}';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _getImageUrl();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.file.name.split('/').last,
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading && _errorMessage == null)
            IconButton(
              icon: const Icon(Icons.zoom_out_map),
              onPressed: _resetZoom,
              tooltip: 'Reset zoom',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Image viewer with zoom/pan
          Center(
            child: _errorMessage != null
                ? _buildErrorWidget()
                : _isLoading
                    ? _buildLoadingWidget()
                    : _buildImageViewer(imageUrl),
          ),
          // Zoom indicator
          if (!_isLoading && _errorMessage == null)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: _buildZoomIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildImageViewer(String imageUrl) {
    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 0.5,
      maxScale: 4.0,
      child: Image.network(
        imageUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            // Image loaded successfully, update state
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_isLoading) {
                setState(() {
                  _isLoading = false;
                });
              }
            });
            return child;
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_errorMessage == null) {
              setState(() {
                _isLoading = false;
                _errorMessage = error.toString();
              });
            }
          });
          return _buildErrorWidget();
        },
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
        SizedBox(height: 16),
        Text(
          'Loading image...',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.error_outline,
          color: Colors.red,
          size: 48,
        ),
        const SizedBox(height: 16),
        const Text(
          'Failed to load image',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? 'Unknown error',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildZoomIndicator() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_size_select_large, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Text(
            '${scale.toStringAsFixed(1)}x',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
