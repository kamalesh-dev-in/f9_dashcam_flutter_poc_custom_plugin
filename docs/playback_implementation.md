# F9 Dashcam Playback Implementation - Complete Documentation

## Table of Contents
1. [Overview](#overview)
2. [Original Implementation Plan](#original-implementation-plan)
3. [Vidure API Analysis](#vidure-api-analysis)
4. [Key Differences Discovered](#key-differences-discovered)
5. [Implementation Journey](#implementation-journey)
6. [Final Implementation Details](#final-implementation-details)
7. [Troubleshooting and Fixes](#troubleshooting-and-fixes)
8. [Lessons Learned](#lessons-learned)

---

## Overview

This document chronicles the complete implementation of the F9 Dashcam playback functionality in a Flutter app. It documents the journey from the initial plan based on generic F9 API documentation to the final implementation adapted for the actual Vidure dashcam API.

**Project:** Flutter F9 Dashcam App
**Feature:** Video/Photo Playback List and Player
**Date:** March 2026
**Device:** EEASY-TECH F9 Dashcam
**API Base:** http://192.168.169.1

---

## Original Implementation Plan

### Initial Scope
The app already had a working live stream screen using RTSP. The goal was to add:
- File browser screen for recorded videos/photos
- Video playback functionality using RTSP
- Bottom navigation to switch between Live Stream and Playback modes

### Original Data Models (Based on Generic F9 API)

```dart
// File folder types
enum FileFolder { loop, emr, event, park }  // 4 folders originally

// File type
enum FileType { picture, video }

// File info model
class F9File {
  final String name;
  final String folder;      // Folder name
  final int duration;       // seconds (0 for pictures)
  final int size;           // KB
  final int createtime;     // Unix timestamp
  final String createtimestr;
  final FileType type;
  final String? gpsPath;    // Optional GPS data path
}
```

### Expected API Response Structure

**Original Assumption:**
```json
{
  "result": 0,
  "files": [
    {
      "name": "REC_20240115_143026.mov",
      "duration": 300,
      "size": 150000,
      "createtime": 1705325426,
      "createtimestr": "20240115143026",
      "type": "video"
    }
  ]
}
```

OR

```json
{
  "result": 0,
  "count": 20,
  "files": [...]
}
```

### Original File List Parsing Logic

```dart
factory FileListResponse.fromJson(String folder, Map<String, dynamic> json) {
  var filesList = json['files'] as List<dynamic?>;

  if (filesList == null || filesList.isEmpty) {
    filesList = json['info'] as List<dynamic?>;  // Fallback
  }

  // Parse files...
}
```

---

## Vidure API Analysis

### Actual API Response Structure

After analyzing the actual Vidure dashcam API responses, the real structure was discovered:

```json
{
  "result": 0,
  "info": [
    {
      "folder": "loop",
      "count": 20,
      "files": [
        {
          "name": "/mnt/card/video_front/20260311_170927_f.ts",
          "duration": -1,
          "size": 85248,
          "createtime": 1773248967,
          "createtimestr": "20260311170927",
          "type": 2
        }
      ]
    }
  ]
}
```

### Critical Discovery

**The files array is NESTED:** `info[0]['files']` not `json['files']`

This was the main cause of the initial parsing failure:
```
Error: type 'Null' is not a subtype of type 'List<dynamic>' in type cast
```

---

## Key Differences Discovered

### 1. JSON Structure Differences

| Aspect | Original Plan | Actual Vidure API |
|--------|---------------|-------------------|
| Files Location | `json['files']` or `json['info']` | `json['info'][0]['files']` |
| Nesting Level | 0 or 1 | 2 (nested inside info array) |
| Count Location | `json['count']` | `json['info'][0]['count']` |

### 2. Field Name Differences

| Field | Original Plan | Actual Vidure API |
|-------|---------------|-------------------|
| Date/Time String | `time` | `createtimestr` |
| File Type | `type` as string ("picture"/"video") | `type` as integer (1=picture, 2=video) |
| Duration | Always positive (seconds) | Can be `-1` for unknown |
| GPS Path | `gpsPath` | `gps` |

### 3. Folder Types

**Original Plan:**
```dart
enum FileFolder { loop, emr, event, park }  // 4 folders
```

**Actual Implementation:**
```dart
enum FileFolder { loop, emr, event, park, photo, race }  // 6 folders
```

Added `photo` and `race` folders that exist on the actual device.

### 4. File Path Format

**Original Assumption:**
```
SD0/Loop/2024-01-15/REC_20240115_143026.mov
```

**Actual API Returns:**
```
/mnt/card/video_front/20260311_170927_f.ts
/mnt/card/video_back/20260311_170923_b.ts
/mnt/card/image_front/20260311_100058_f.jpg
```

---

## Implementation Journey

### Phase 1: Initial Implementation
- Created data models based on generic F9 API documentation
- Implemented `FileListResponse.fromJson` expecting direct `files` array
- Built UI components: FileThumbnail, FileListItem, FileGridItem
- Created PlaybackListScreen with folder tabs
- Created VideoPlayerScreen with RTSP playback

### Phase 2: First Testing Attempt
```
Error: type 'Null' is not a subtype of type 'List<dynamic>' in type cast
```

The API was returning data but parsing failed because:
- Code tried to access `json['files']` → returned `null`
- Code tried to access `json['info']` → returned array, but not directly files

### Phase 3: API Response Analysis

Actual API response logged:
```json
{"result":0,"info":[{"folder":"loop","count":20,"files":[{"name":"/mnt/card/video_front/20260311_170927_f.ts","duration":-1,"size":85248,"createtime":1773248967,"createtimestr":"20260311170927","type":2}...
```

The issue was clear: files are at `info[0]['files']`

### Phase 4: Fixing the Parsing

Updated `FileListResponse.fromJson`:

```dart
factory FileListResponse.fromJson(String folder, Map<String, dynamic> json) {
  final fileList = <F9File>[];
  List<dynamic>? filesList;

  // The actual API structure: {"result": 0, "info": [{folder, count, files: [...]}]}
  final info = json['info'];
  if (info is List && info.isNotEmpty) {
    final firstInfo = info[0];
    if (firstInfo is Map<String, dynamic>) {
      filesList = firstInfo['files'] as List<dynamic>?;
      print('[FileListResponse] Found files in info[0][files]: ${filesList?.length ?? 0} items');
    }
  }

  // Fallback: try "files" array directly at root
  if (filesList == null) {
    filesList = json['files'] as List<dynamic>?;
  }

  // Fallback: try "info" as direct files array
  if (filesList == null && info is List) {
    filesList = info;
  }

  // Parse files...
}
```

### Phase 5: Fixing Individual File Parsing

Updated `F9File.fromJson` to handle actual field names:

```dart
factory F9File.fromJson(Map<String, dynamic> json) {
  // Handle time field - try createtimestr first (API format)
  final timeStr = json['createtimestr'] as String? ?? json['time'] as String? ?? '';

  // Handle type - API returns int (1=picture, 2=video)
  FileType? fileType;
  final typeInt = json['type'] as int?;
  if (typeInt != null) {
    fileType = typeInt == 2 ? FileType.video : FileType.picture;
  }

  // Handle duration - API may return -1 for unknown
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
```

---

## Final Implementation Details

### Files Created/Modified

**New Files Created:**
- `lib/models/f9_file.dart` - Data models with API parsing
- `lib/screens/playback_list_screen.dart` - File browser UI
- `lib/screens/video_player_screen.dart` - Video player screen
- `lib/widgets/file_thumbnail.dart` - Thumbnail component
- `lib/widgets/file_list_item.dart` - List item component
- `lib/widgets/file_grid_item.dart` - Grid item component

**Modified Files:**
- `lib/main.dart` - Added bottom navigation with IndexedStack
- `lib/services/rtsp_service.dart` - Added playback API methods

### API Endpoints Used

| Action | Endpoint | Method |
|--------|----------|--------|
| Get file list | `/app/getfilelist?folder={type}&start={n}&end={n}` | GET |
| Get thumbnail | `/app/getthumbnail?file={path}` | GET |
| Delete file | `/app/deletefile?file={path}` | GET |
| Enter playback | `/app/playback?param=enter` | GET |
| Exit playback | `/app/playback?param=exit` | GET |
| Video stream (RTSP) | `rtsp://192.168.169.1:554/{path}` | RTSP |

### Folder Types and API Values

| Display Name | Enum Value | API Parameter |
|--------------|------------|---------------|
| Loop | `FileFolder.loop` | `loop` |
| Emergency | `FileFolder.emr` | `emr` |
| Event | `FileFolder.event` | `event` |
| Parking | `FileFolder.park` | `park` |
| Photo | `FileFolder.photo` | `photo` |
| Race | `FileFolder.race` | `race` |

### File Type Detection

```dart
// From API integer
type: 1 → FileType.picture
type: 2 → FileType.video

// From filename (fallback)
.mp4, .mov, .avi → FileType.video
others → FileType.picture
```

---

## Troubleshooting and Fixes

### Issue 1: Gradle Build Hanging

**Problem:**
```
Running Gradle task 'assembleDebug'... (taking 10+ minutes)
```

**Cause:** Heap size set too high (8GB) causing excessive GC pauses.

**Fix:**
```properties
# android/gradle.properties
org.gradle.jvmargs=-Xmx2G  # Changed from -Xmx8G
# Removed deprecated: android.enableBuildCache
```

### Issue 2: shared_preferences Dependency

**Problem:** App stuck on Gradle build forever after adding shared_preferences.

**Cause:** Native build issues with the package.

**Fix:** Removed shared_preferences, used in-memory state for view toggle.

### Issue 3: Uint8List Type Error

**Problem:**
```
The argument type 'List<int>' can't be assigned to the parameter type 'Uint8List'
```

**Fix:**
```dart
// Changed return type
Future<Uint8List> getThumbnail(String filePath) async {
  return response.bodyBytes;  // Already Uint8List
}
```

### Issue 4: Files Not Showing (Main Issue)

**Problem:** "No files in loop, emergency, etc."

**Logs:**
```
File list response: {"result":0,"info":[{folder,count,files:[...]}]}
JSON parsing failed: type 'Null' is not a subtype of type 'List<dynamic>'
```

**Root Cause:** Files nested at `info[0]['files']` not at root level.

**Fix:** Updated parsing to navigate nested structure (shown in Phase 4 above).

---

## Lessons Learned

### 1. API Documentation vs Reality

Generic F9 API documentation showed a different structure than the actual Vidure implementation. Always test with real device responses.

### 2. Defensive Programming

The final implementation uses multiple fallback strategies:
1. Try `info[0]['files']` (Vidure format)
2. Try `json['files']` (generic format)
3. Try `json['info']` as direct array

This makes the code more robust across different device models.

### 3. Field Name Variations

Handle multiple possible field names:
```dart
final timeStr = json['createtimestr'] ?? json['time'] ?? '';
```

### 4. Type Conversion

Don't assume types match documentation:
```dart
// API returns int, not string
final typeInt = json['type'] as int?;
fileType = typeInt == 2 ? FileType.video : FileType.picture;
```

### 5. Edge Case Handling

```dart
// Duration can be -1 for unknown
finalDuration = durationVal < 0 ? 0 : durationVal;
```

---

## Verification and Testing

### Successful Implementation Confirmed by Logs

```
[FileListResponse] Found files in info[0][files]: 20 items
[FileListResponse] Parsed folder=loop, count=20, files=20
[RtspService] File list parsed: 20 files, 20 in list
[PlaybackList] Loaded 20 files from Loop
[PlaybackList] File: /mnt/card/video_front/20260311_171528_f.ts, type: FileType.video, size: 173.8 KB
[RtspService] Thumbnail response: 200
[RtspService] Thumbnail fetched: 20327 bytes
```

### Features Working

- ✅ 20 files loading in Loop folder
- ✅ Thumbnails fetching successfully
- ✅ Files displaying with correct type, size, and date
- ✅ Live Stream RTSP connection working
- ✅ Bottom navigation with state preservation
- ✅ List and Grid view toggle
- ✅ Folder tabs (Loop, Emergency, Event, Parking, Photo, Race)

---

## Code Comparison Summary

### Before (Original Plan)

```dart
// Expected simple structure
var filesList = json['files'] as List<dynamic?>;

// Expected string type
type: json['type'] as String

// Expected direct time field
time: json['time'] as String
```

### After (Vidure Implementation)

```dart
// Handle nested structure
final info = json['info'];
if (info is List && info.isNotEmpty) {
  filesList = info[0]['files'];
}

// Handle integer type with conversion
final typeInt = json['type'] as int?;
fileType = typeInt == 2 ? FileType.video : FileType.picture;

// Handle createtimestr with fallback
time: json['createtimestr'] ?? json['time'] ?? ''
```

---

## Conclusion

The implementation journey highlighted the importance of:
1. Testing with real API responses early
2. Building flexible parsing with fallbacks
3. Handling edge cases (null values, unknown types)
4. Comprehensive logging for debugging

The final implementation successfully handles the Vidure dashcam API while maintaining flexibility for potential variations in other F9-compatible devices.

---

**Generated:** March 11, 2026
**Author:** Claude (with user guidance and Vidure API analysis)
**Project:** Flutter F9 Dashcam POC
**Status:** ✅ Complete and Working
