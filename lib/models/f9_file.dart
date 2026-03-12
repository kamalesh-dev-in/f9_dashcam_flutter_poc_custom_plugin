/// File folder types on the dashcam
enum FileFolder {
  loop,
  emr,
  event,
  park,
  photo,
  race;

  /// Get the API parameter value for this folder
  String get apiValue {
    switch (this) {
      case FileFolder.loop:
        return 'loop';
      case FileFolder.emr:
        return 'emr';
      case FileFolder.event:
        return 'event';
      case FileFolder.park:
        return 'park';
      case FileFolder.photo:
        return 'photo';
      case FileFolder.race:
        return 'race';
    }
  }

  /// Get display name for this folder
  String get displayName {
    switch (this) {
      case FileFolder.loop:
        return 'Loop';
      case FileFolder.emr:
        return 'Emergency';
      case FileFolder.event:
        return 'Event';
      case FileFolder.park:
        return 'Parking';
      case FileFolder.photo:
        return 'Photo';
      case FileFolder.race:
        return 'Race';
    }
  }

  /// Parse from API string value
  static FileFolder? fromApiValue(String value) {
    for (final folder in FileFolder.values) {
      if (folder.apiValue == value.toLowerCase()) {
        return folder;
      }
    }
    return null;
  }
}

/// File type (picture or video)
enum FileType {
  picture,
  video;

  /// Get the API parameter value for this file type
  String get apiValue {
    switch (this) {
      case FileType.picture:
        return 'picture';
      case FileType.video:
        return 'video';
    }
  }

  /// Detect file type from filename
  static FileType fromFileName(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    if (ext == 'mp4' || ext == 'mov' || ext == 'avi') {
      return FileType.video;
    }
    return FileType.picture;
  }

  /// Parse from API string value
  static FileType? fromApiValue(String value) {
    for (final type in FileType.values) {
      if (type.apiValue == value.toLowerCase()) {
        return type;
      }
    }
    return null;
  }
}

/// Represents a file (video or picture) on the dashcam SD card
class F9File {
  /// File name (e.g., "20240101_120000_0.mp4")
  final String name;

  /// File size in bytes
  final int size;

  /// Creation time as string (e.g., "20240101120000")
  final String time;

  /// Duration in seconds (0 for pictures)
  final int duration;

  /// GPS data file path (e.g., "/GPSdata/20240101_120000 GPS.txt")
  final String? gps;

  /// Gyroscope data file path
  final String? gyro;

  /// Lock status
  final int? lock;

  /// Camera position (0=front, 1=rear)
  final int? position;

  /// File type
  final FileType type;

  F9File({
    required this.name,
    required this.size,
    required this.time,
    required this.duration,
    this.gps,
    this.gyro,
    this.lock,
    this.position,
    FileType? type,
  }) : type = type ?? FileType.fromFileName(name);

  /// Get the RTSP playback URL
  /// Format: rtsp://192.168.169.1:554/{filename}
  String get rtspPath {
    return name;
  }

  /// Get the HTTP playback URL
  /// Format: http://192.168.169.1/{filename}
  String get httpPath {
    return name;
  }

  /// Get the full HTTP URL for playback
  String get playbackUrl {
    return 'http://192.168.169.1/$name';
  }

  /// Check if this file has GPS data
  bool get hasGps => gps != null && gps!.isNotEmpty;

  /// Check if this file has gyroscope data
  bool get hasGyro => gyro != null && gyro!.isNotEmpty;

  /// Get formatted duration string (e.g., "5:00" or "0:45")
  String get durationString {
    if (duration <= 0) return '';
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get formatted size string (e.g., "15.2 MB")
  String get sizeString {
    const kb = 1024;
    const mb = kb * 1024;

    if (size >= mb) {
      return '${(size / mb).toStringAsFixed(1)} MB';
    } else if (size >= kb) {
      return '${(size / kb).toStringAsFixed(1)} KB';
    } else {
      return '$size B';
    }
  }

  /// Get formatted date string
  String get dateString {
    try {
      // Format: "20240101120000" -> "2024-01-01 12:00:00"
      if (time.length >= 14) {
        final year = time.substring(0, 4);
        final month = time.substring(4, 6);
        final day = time.substring(6, 8);
        final hour = time.substring(8, 10);
        final minute = time.substring(10, 12);
        final second = time.substring(12, 14);
        return '$year-$month-$day $hour:$minute:$second';
      }
      return time;
    } catch (_) {
      return time;
    }
  }

  /// Parse from API JSON response
  factory F9File.fromJson(Map<String, dynamic> json) {
    // Handle time field - try createtimestr first (API format), fallback to time
    final timeStr = json['createtimestr'] as String? ?? json['time'] as String? ?? '';

    // Handle type - API returns int (1=picture, 2=video)
    FileType? fileType;
    final typeInt = json['type'] as int?;
    if (typeInt != null) {
      fileType = typeInt == 2 ? FileType.video : FileType.picture;
    }

    // Handle duration - API may return -1 for unknown, convert to 0
    final durationVal = json['duration'] as int? ?? 0;
    final finalDuration = durationVal < 0 ? 0 : durationVal;

    return F9File(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      time: timeStr,
      duration: finalDuration,
      gps: json['gps'] as String?,
      gyro: json['gyro'] as String?,
      lock: json['lock'] as int?,
      position: json['position'] as int?,
      type: fileType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'size': size,
      'time': time,
      'duration': duration,
      if (gps != null) 'gps': gps,
      if (gyro != null) 'gyro': gyro,
      if (lock != null) 'lock': lock,
      if (position != null) 'position': position,
    };
  }

  @override
  String toString() {
    return 'F9File(name: $name, size: $size, duration: $duration, type: $type)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is F9File && other.name == name && other.time == time;
  }

  @override
  int get hashCode => Object.hash(name, time);
}

/// Response from file list API endpoint
class FileListResponse {
  /// Folder type
  final FileFolder folder;

  /// Total count of files in this folder
  final int count;

  /// List of files
  final List<F9File> files;

  FileListResponse({
    required this.folder,
    required this.count,
    required this.files,
  });

  /// Parse from API JSON response
  /// The API returns: {"result": 0, "info": [...]}
  /// C1S format: info[0]=videos, info[1]=other, info[2]=photos
  factory FileListResponse.fromJson(String folder, Map<String, dynamic> json) {
    final fileList = <F9File>[];

    List<dynamic>? filesList;

    // The actual API structure: {"result": 0, "info": [...]}
    final info = json['info'];
    if (info is List && info.isNotEmpty) {
      // C1S format: info is an array where info[2] contains photos
      // For photo folder, try info[2] first
      if (folder.toLowerCase() == 'photo' && info.length > 2) {
        filesList = info[2] as List<dynamic>?;
        if (filesList != null) {
          print('[FileListResponse] Found photo files in info[2]: ${filesList.length} items');
        }
      }

      // Standard format: info[0] contains the file list
      if (filesList == null) {
        final firstInfo = info[0];
        if (firstInfo is Map<String, dynamic>) {
          filesList = firstInfo['files'] as List<dynamic>?;
          if (filesList != null) {
            print('[FileListResponse] Found files in info[0][files]: ${filesList.length} items');
          }
        } else if (firstInfo is List) {
          // info[0] might be a direct array
          filesList = firstInfo;
          print('[FileListResponse] Found files in info[0] as array: ${filesList.length} items');
        }
      }
    }

    // Fallback: try "files" array directly at root
    if (filesList == null) {
      filesList = json['files'] as List<dynamic>?;
      if (filesList != null) {
        print('[FileListResponse] Found files at root: ${filesList.length} items');
      }
    }

    // Fallback: try "info" as direct files array
    if (filesList == null && info is List) {
      filesList = info;
      print('[FileListResponse] Using info array directly: ${filesList.length} items');
    }

    if (filesList != null) {
      for (final item in filesList) {
        if (item != null && item is Map<String, dynamic>) {
          try {
            fileList.add(F9File.fromJson(item));
          } catch (e) {
            // Skip invalid entries
            print('[FileListResponse] Failed to parse file: $item, error: $e');
            continue;
          }
        }
      }
    }

    // Get count from API response or fallback to file list length
    int count = fileList.length;
    if (info is List && info.isNotEmpty && info[0] is Map<String, dynamic>) {
      count = (info[0] as Map<String, dynamic>)['count'] as int? ?? fileList.length;
    } else {
      count = json['count'] as int? ?? fileList.length;
    }

    print('[FileListResponse] Parsed folder=$folder, count=$count, files=${fileList.length}');

    return FileListResponse(
      folder: FileFolder.fromApiValue(folder) ?? FileFolder.loop,
      count: count,
      files: fileList,
    );
  }
}
