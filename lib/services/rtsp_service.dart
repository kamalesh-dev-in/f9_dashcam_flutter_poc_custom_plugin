import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import '../models/f9_file.dart';

/// RTSP stream configuration for EEASY-TECH dashcam
class RtspConfig {
  /// Base URL for the dashcam HTTP API
  static const String baseUrl = 'http://192.168.169.1';

  /// Default RTSP URL for the dashcam
  static const String defaultRtspUrl = 'rtsp://192.168.169.1:554';

  /// Stream resolution
  static const int width = 960;
  static const int height = 540;

  /// Stream FPS
  static const int fps = 25;

  /// Camera channels
  static const List<String> cameraChannels = ['0', '1', '2'];

  /// Camera names
  static const List<String> cameraNames = ['Front', 'Rear', 'PiP'];

  /// Heartbeat interval (5 seconds as per documentation)
  static const Duration heartbeatInterval = Duration(seconds: 5);

  /// Enable debug logging
  static const bool debug = true;
}

/// Connection status for the RTSP stream
enum StreamConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Service class for managing RTSP streaming connection
class RtspService {
  final String rtspUrl;
  final String baseUrl;
  Player? _player;
  StreamConnectionStatus _status = StreamConnectionStatus.disconnected;
  String? _errorMessage;
  Timer? _heartbeatTimer;
  MediaInfo? _mediaInfo;

  /// List of connection step results for debugging
  final List<String> _connectionLog = [];

  RtspService({String? rtspUrl, String? baseUrl})
      : rtspUrl = rtspUrl ?? RtspConfig.defaultRtspUrl,
        baseUrl = baseUrl ?? RtspConfig.baseUrl;

  /// Get current player instance
  Player? get player => _player;

  /// Get current connection status
  StreamConnectionStatus get status => _status;

  /// Get error message if any
  String? get errorMessage => _errorMessage;

  /// Get media info if available
  MediaInfo? get mediaInfo => _mediaInfo;

  /// Get connection log for debugging
  List<String> get connectionLog => List.unmodifiable(_connectionLog);

  void _log(String message) {
    _connectionLog.add(message);
    if (RtspConfig.debug) {
      developer.log('RtspService: $message', name: 'dashcam.rtsp');
      // ignore: avoid_print
      print('[RtspService] $message'); // Also print to console for easy debugging
    }
  }

  /// Initialize the player with RTSP configuration
  void initializePlayer() {
    if (_player != null) {
      _player!.dispose();
    }

    _player = Player();
    _status = StreamConnectionStatus.disconnected;
    _errorMessage = null;
    _connectionLog.clear();
    _log('Player initialized');
  }

  /// Send enter-recorder request
  /// Prerequisite step before opening RTSP stream (marked as optional in docs)
  Future<bool> _enterRecorder() async {
    final url = '$baseUrl/app/enterrecorder';
    _log('Attempting enter-recorder: $url');

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      _log('Enter-recorder response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        _log('Enter-recorder: SUCCESS');
        return true;
      } else {
        _log('Enter-recorder: FAILED (status ${response.statusCode})');
        _errorMessage = 'Enter recorder failed: ${response.statusCode}';
        return false;
      }
    } catch (e) {
      _log('Enter-recorder: ERROR - $e');
      _errorMessage = 'Enter recorder error: $e';
      return false;
    }
  }

  /// Send heartbeat request to keep connection alive
  /// Should be called regularly (every 5 seconds)
  Future<void> _sendHeartbeat() async {
    final url = '$baseUrl/app/getparamvalue?param=rec';
    _log('Sending heartbeat: $url');

    try {
      final response = await http.get(
        Uri.parse(url),
      ).timeout(const Duration(seconds: 3));

      _log('Heartbeat response: ${response.statusCode} - ${response.body}');

      if (response.statusCode != 200) {
        _log('Heartbeat: FAILED (status ${response.statusCode})');
        _status = StreamConnectionStatus.error;
        _errorMessage = 'Heartbeat failed: ${response.statusCode}';
      }
    } catch (e) {
      _log('Heartbeat: ERROR - $e');
      _status = StreamConnectionStatus.error;
      _errorMessage = 'Heartbeat error: $e';
    }
  }

  /// Fetch media info to confirm stream parameters
  /// Returns parsed MediaInfo or null if request fails
  Future<MediaInfo?> _getMediaInfo() async {
    final url = '$baseUrl/app/getmediainfo';
    _log('Fetching media info: $url');

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      _log('Media info response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        // Try to parse JSON response
        try {
          return MediaInfo.fromJson(response.body);
        } catch (e) {
          _log('Media info parsing failed: $e');
          // Return default info even if parsing fails
          return MediaInfo.defaults();
        }
      } else {
        _log('Media info: FAILED (status ${response.statusCode})');
        _errorMessage = 'Get media info failed: ${response.statusCode}';
        return MediaInfo.defaults(); // Return defaults on failure
      }
    } catch (e) {
      _log('Media info: ERROR - $e');
      _errorMessage = 'Get media info error: $e';
      return MediaInfo.defaults(); // Return defaults on error
    }
  }

  /// Start heartbeat timer
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer =
        Timer.periodic(RtspConfig.heartbeatInterval, (_) {
      _sendHeartbeat();
    });
    _log('Heartbeat timer started (${RtspConfig.heartbeatInterval.inSeconds}s interval)');
  }

  /// Stop heartbeat timer
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _log('Heartbeat timer stopped');
  }

  /// Switch camera lens on the dashcam
  /// API endpoint: GET http://192.168.169.1/app/setparamvalue?param=switchcam&value=X
  /// [cameraIndex] is the camera index (0=Front, 1=Rear, 2=PiP)
  Future<bool> _switchCameraApi(int cameraIndex) async {
    final url = '$baseUrl/app/setparamvalue?param=switchcam&value=$cameraIndex';
    _log('Switching camera via API: $url');

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      _log('Switch camera API response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        _log('Camera switch: SUCCESS (camera $cameraIndex)');
        return true;
      } else {
        _log('Camera switch: FAILED (status ${response.statusCode})');
        _errorMessage = 'Switch camera failed: ${response.statusCode}';
        return false;
      }
    } catch (e) {
      _log('Camera switch: ERROR - $e');
      _errorMessage = 'Switch camera error: $e';
      return false;
    }
  }

  /// Connect to the RTSP stream
  /// [cameraIndex] is the camera channel (0=Front, 1=Rear, 2=PiP)
  /// [skipPrerequisites] if true, skips the optional HTTP prerequisites
  Future<void> connect({
    int cameraIndex = 0,
    bool skipPrerequisites = false,
  }) async {
    if (_player == null) {
      initializePlayer();
    }

    _status = StreamConnectionStatus.connecting;
    _errorMessage = null;
    _log('=== Starting connection (camera: $cameraIndex) ===');

    try {
      if (!skipPrerequisites) {
        // Prerequisite 1: Send enter-recorder request (OPTIONAL per docs)
        _log('Step 1: Enter recorder (optional)...');
        final entered = await _enterRecorder();
        if (!entered) {
          _log('WARNING: Enter recorder failed, but continuing (marked optional in docs)');
          // Don't throw - this is optional per documentation
        }

        // Prerequisite 2: Switch camera if needed (not front camera)
        if (cameraIndex != 0) {
          _log('Step 2: Switching camera to ${RtspConfig.cameraNames[cameraIndex]}...');
          final switched = await _switchCameraApi(cameraIndex);
          if (!switched) {
            _log('WARNING: Camera switch API failed, but continuing');
          }
          // Wait a moment for camera to switch
          await Future.delayed(const Duration(milliseconds: 300));
        }

        // Prerequisite 3: Fetch media info (OPTIONAL per docs)
        _log('Step 3: Get media info (optional)...');
        _mediaInfo = await _getMediaInfo();
        if (_mediaInfo != null) {
          _log('Media info: $_mediaInfo');
        }
      } else {
        _log('Skipping prerequisites (skipPrerequisites=true)');
      }

      // Step 4: Open RTSP stream
      final url = '$rtspUrl?channel=${RtspConfig.cameraChannels[cameraIndex]}';
      _log('Step 4: Opening RTSP stream: $url');

      await _player!.open(Media(url), play: true);
      _log('RTSP stream opened successfully');

      // Listen for stream state changes
      _player!.stream.completed.listen((completed) {
        if (completed) {
          _log('Stream completed');
          _status = StreamConnectionStatus.disconnected;
          _stopHeartbeat();
        }
      });

      _player!.stream.error.listen((error) {
        _log('Stream error: $error');
        _status = StreamConnectionStatus.error;
        _errorMessage = error.toString();
      });

      // Prerequisite 4: Start heartbeat timer
      _startHeartbeat();

      _status = StreamConnectionStatus.connected;
      _log('=== Connection established ===');
    } catch (e) {
      _log('=== Connection FAILED: $e ===');
      _status = StreamConnectionStatus.error;
      _errorMessage = e.toString();
      _stopHeartbeat();
      rethrow;
    }
  }

  /// Disconnect from the RTSP stream
  void disconnect() {
    _log('Disconnecting...');
    _stopHeartbeat();
    _player?.stop();
    _status = StreamConnectionStatus.disconnected;
    _log('Disconnected');
  }

  /// Reconnect to the stream
  Future<void> reconnect({
    int cameraIndex = 0,
    bool skipPrerequisites = false,
  }) async {
    disconnect();
    await connect(cameraIndex: cameraIndex, skipPrerequisites: skipPrerequisites);
  }

  /// Switch camera
  Future<void> switchCamera(int cameraIndex) async {
    if (cameraIndex < 0 || cameraIndex >= RtspConfig.cameraChannels.length) {
      throw ArgumentError('Invalid camera index: $cameraIndex');
    }
    _log('=== Switching to camera $cameraIndex (${RtspConfig.cameraNames[cameraIndex]}) ===');

    // Step 1: Call the API to switch camera on the device
    final switched = await _switchCameraApi(cameraIndex);
    if (!switched) {
      _log('WARNING: Camera switch API failed, but continuing with stream reconnect');
    }

    // Step 2: Reconnect the RTSP stream with the new camera
    // Disconnect current stream first
    disconnect();

    // Wait a moment for the camera to switch
    await Future.delayed(const Duration(milliseconds: 500));

    // Reconnect with the new camera
    await connect(cameraIndex: cameraIndex);
  }

  /// Dispose of resources
  void dispose() {
    _log('Disposing service...');
    _stopHeartbeat();
    _player?.dispose();
    _player = null;
    _status = StreamConnectionStatus.disconnected;
  }

  /// Get stream info
  Map<String, dynamic> getStreamInfo() {
    return {
      'url': rtspUrl,
      'width': RtspConfig.width,
      'height': RtspConfig.height,
      'fps': RtspConfig.fps,
      'status': _status.toString(),
      'mediaInfo': _mediaInfo?.toString(),
      'connectionLog': _connectionLog,
    };
  }

  // ==================== PLAYBACK API METHODS ====================

  /// Get file list from the dashcam
  /// API endpoint: GET /app/getfilelist?folder={type}&start={n}&end={n}
  /// Note: end is exclusive, so for 20 items: start=0&end=19
  Future<FileListResponse> getFileList({
    FileFolder? folder,
    int? start,
    int? end,
  }) async {
    final folderType = folder?.apiValue ?? FileFolder.loop.apiValue;
    final startIdx = start ?? 0;
    final endIdx = end ?? (startIdx + 20 - 1); // Default 20 items per page
    final url = '$baseUrl/app/getfilelist?folder=$folderType&start=$startIdx&end=$endIdx';
    _log('Getting file list: $url');

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30)); // Increased timeout

      _log('File list response status: ${response.statusCode}');
      _log('File list response body (first 500 chars): ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final fileList = FileListResponse.fromJson(folderType, json);
          _log('File list parsed: ${fileList.count} files, ${fileList.files.length} in list');
          return fileList;
        } catch (e) {
          _log('JSON parsing failed: $e');
          _log('Response body that failed to parse: ${response.body}');
          // Return empty list but log the error
          return FileListResponse(
            folder: folder ?? FileFolder.loop,
            count: 0,
            files: [],
          );
        }
      } else {
        _log('File list: FAILED (status ${response.statusCode})');
        throw Exception('Get file list failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _log('File list: ERROR - $e');
      _errorMessage = 'Get file list error: $e';
      rethrow;
    }
  }

  /// Get thumbnail image bytes for a file
  /// API endpoint: GET /app/getthumbnail?file={path}
  Future<Uint8List> getThumbnail(String filePath) async {
    final url = '$baseUrl/app/getthumbnail?file=$filePath';
    _log('Getting thumbnail: $url');

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      _log('Thumbnail response: ${response.statusCode}');

      if (response.statusCode == 200) {
        _log('Thumbnail fetched: ${response.bodyBytes.length} bytes');
        return response.bodyBytes;
      } else {
        _log('Thumbnail: FAILED (status ${response.statusCode})');
        throw Exception('Get thumbnail failed: ${response.statusCode}');
      }
    } catch (e) {
      _log('Thumbnail: ERROR - $e');
      rethrow;
    }
  }

  /// Delete a file from the SD card
  /// API endpoint: GET /app/deletefile?file={path}
  Future<bool> deleteFile(String filePath) async {
    final url = '$baseUrl/app/deletefile?file=$filePath';
    _log('Deleting file: $url');

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      _log('Delete file response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        _log('File deleted successfully');
        return true;
      } else {
        _log('Delete file: FAILED (status ${response.statusCode})');
        _errorMessage = 'Delete file failed: ${response.statusCode}';
        return false;
      }
    } catch (e) {
      _log('Delete file: ERROR - $e');
      _errorMessage = 'Delete file error: $e';
      return false;
    }
  }

  /// Enter playback mode
  /// API endpoint: GET /app/playback?param=enter
  Future<bool> enterPlaybackMode() async {
    final url = '$baseUrl/app/playback?param=enter';
    _log('Entering playback mode: $url');

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      _log('Enter playback response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        _log('Playback mode entered successfully');
        return true;
      } else {
        _log('Enter playback: FAILED (status ${response.statusCode})');
        _errorMessage = 'Enter playback failed: ${response.statusCode}';
        return false;
      }
    } catch (e) {
      _log('Enter playback: ERROR - $e');
      _errorMessage = 'Enter playback error: $e';
      return false;
    }
  }

  /// Exit playback mode
  /// API endpoint: GET /app/playback?param=exit
  Future<bool> exitPlaybackMode() async {
    final url = '$baseUrl/app/playback?param=exit';
    _log('Exiting playback mode: $url');

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      _log('Exit playback response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        _log('Playback mode exited successfully');
        return true;
      } else {
        _log('Exit playback: FAILED (status ${response.statusCode})');
        _errorMessage = 'Exit playback failed: ${response.statusCode}';
        return false;
      }
    } catch (e) {
      _log('Exit playback: ERROR - $e');
      _errorMessage = 'Exit playback error: $e';
      return false;
    }
  }

  /// Build RTSP URL for file playback
  /// [filePath] is the file path (e.g., "SD0/Loop/2024-01-15/REC_20240115_143026.mov")
  /// [port] is the RTSP port (default 554, can also use 8554)
  String buildPlaybackRtspUrl(String filePath, {int port = 554}) {
    return 'rtsp://192.168.169.1:$port/$filePath';
  }
}

/// Media information from the dashcam
class MediaInfo {
  final String? rtspUrl;
  final String? transport;
  final int? port;
  final String? videoCodec;
  final String? audioCodec;
  final int? width;
  final int? height;
  final int? fps;

  MediaInfo({
    this.rtspUrl,
    this.transport,
    this.port,
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
    this.fps,
  });

  /// Default media info when API fails
  factory MediaInfo.defaults() {
    return MediaInfo(
      rtspUrl: 'rtsp://192.168.169.1',
      transport: 'tcp',
      port: 554,
      videoCodec: 'H.264',
      audioCodec: 'AAC',
      width: 960,
      height: 540,
      fps: 25,
    );
  }

  /// Parse media info from JSON response
  /// Expected format:
  /// {"result": 0, "info": {"rtsp": "rtsp://192.168.169.1", "transport": "tcp", "port": 5000}}
  factory MediaInfo.fromJson(String jsonStr) {
    try {
      String? rtsp;
      String? transport;
      int? port;

      // Extract rtsp URL
      final rtspMatch = RegExp(r'"rtsp"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
      if (rtspMatch != null) {
        rtsp = rtspMatch.group(1);
      }

      // Extract transport
      final transportMatch = RegExp(r'"transport"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
      if (transportMatch != null) {
        transport = transportMatch.group(1);
      }

      // Extract port
      final portMatch = RegExp(r'"port"\s*:\s*(\d+)').firstMatch(jsonStr);
      if (portMatch != null) {
        port = int.tryParse(portMatch.group(1)!);
      }

      return MediaInfo.defaults().copyWith(
        rtspUrl: rtsp,
        transport: transport,
        port: port,
      );
    } catch (e) {
      return MediaInfo.defaults();
    }
  }

  MediaInfo copyWith({
    String? rtspUrl,
    String? transport,
    int? port,
    String? videoCodec,
    String? audioCodec,
    int? width,
    int? height,
    int? fps,
  }) {
    return MediaInfo(
      rtspUrl: rtspUrl ?? this.rtspUrl,
      transport: transport ?? this.transport,
      port: port ?? this.port,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
    );
  }

  @override
  String toString() {
    return 'MediaInfo(rtsp: $rtspUrl, transport: $transport, port: $port, '
        'video: $videoCodec, audio: $audioCodec, '
        '${width}x$height @ ${fps}fps)';
  }
}
