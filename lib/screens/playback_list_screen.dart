import 'package:flutter/material.dart';
import '../models/f9_file.dart';
import '../services/rtsp_service.dart';
import '../widgets/file_list_item.dart';
import '../widgets/file_grid_item.dart';
import 'video_player_screen.dart';

enum ViewMode { list, grid }

/// Screen for browsing and playing back recorded videos and photos
class PlaybackListScreen extends StatefulWidget {
  const PlaybackListScreen({super.key});

  @override
  State<PlaybackListScreen> createState() => _PlaybackListScreenState();
}

class _PlaybackListScreenState extends State<PlaybackListScreen>
    with SingleTickerProviderStateMixin {
  late final RtspService _rtspService;
  late final TabController _tabController;

  FileFolder _selectedFolder = FileFolder.loop;
  ViewMode _viewMode = ViewMode.list;
  List<F9File> _files = [];
  bool _isLoading = false;
  String? _errorMessage;

  static const int _pageSize = 20;  // Default page size per API docs
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _rtspService = RtspService();
    _tabController = TabController(length: FileFolder.values.length, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _rtspService.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      _selectedFolder = FileFolder.values[_tabController.index];
      _currentPage = 0;
      _files.clear();
    });
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _rtspService.getFileList(
        folder: _selectedFolder,
        start: _currentPage * _pageSize,
        end: (_currentPage + 1) * _pageSize - 1,
      );

      if (mounted) {
        setState(() {
          _files = response.files;
          _isLoading = false;
        });
      }

      // Debug: print log to console
      print('[PlaybackList] Loaded ${response.files.length} files from ${_selectedFolder.displayName}');
      for (var file in response.files) {
        print('[PlaybackList] File: ${file.name}, type: ${file.type}, size: ${file.sizeString}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
      // Debug: print error and connection log
      print('[PlaybackList] Error loading files: $e');
      print('[PlaybackList] Connection log: ${_rtspService.connectionLog}');
    }
  }

  Future<void> _handleRefresh() async {
    _currentPage = 0;
    await _loadFiles();
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list;
    });
  }

  void _openFile(F9File file) {
    if (file.type == FileType.video) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(file: file),
        ),
      ).then((_) {
        _loadFiles();
      });
    } else {
      _showImageDialog(file);
    }
  }

  void _showImageDialog(F9File file) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Image viewer coming soon',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleDeleteFile(F9File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Delete File', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete ${file.name}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deleted = await _rtspService.deleteFile(file.httpPath);
      if (deleted && mounted) {
        setState(() {
          _files.remove(file);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File deleted')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete file')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Playback'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_viewMode == ViewMode.list ? Icons.grid_view : Icons.list),
            onPressed: _toggleViewMode,
            tooltip: _viewMode == ViewMode.list ? 'Grid view' : 'List view',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue.shade700,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: FileFolder.values.map((folder) {
            return Tab(text: folder.displayName);
          }).toList(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(height: 16),
            Text(
              'Loading files...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorWidget();
    }

    if (_files.isEmpty) {
      return _buildEmptyWidget();
    }

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: Colors.white,
      backgroundColor: Colors.grey.shade900,
      child: _buildFileList(),
    );
  }

  Widget _buildFileList() {
    if (_viewMode == ViewMode.list) {
      return ListView.builder(
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final file = _files[index];
          return FileListItem(
            file: file,
            onTap: () => _openFile(file),
            onLongPress: () => _handleDeleteFile(file),
          );
        },
      );
    } else {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.85,
        ),
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final file = _files[index];
          return FileGridItem(
            file: file,
            onTap: () => _openFile(file),
            onLongPress: () => _handleDeleteFile(file),
          );
        },
      );
    }
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No files in ${_selectedFolder.displayName}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pull to refresh',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Error loading files',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Debug Log:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _rtspService.connectionLog.join('\n'),
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _handleRefresh,
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
    );
  }
}
