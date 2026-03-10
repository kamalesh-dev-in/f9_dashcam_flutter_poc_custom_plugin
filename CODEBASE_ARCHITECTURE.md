# Flutter Dashcam Live Streaming - Codebase Architecture

This document explains how the Flutter Dashcam Live Streaming POC application works, including its architecture, data flow, and how it handles user input.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Architecture Overview](#architecture-overview)
3. [Component Details](#component-details)
4. [Flow Diagrams](#flow-diagrams)
5. [Input Handling](#input-handling)
6. [API Integration](#api-integration)

---

## Project Structure

```
lib/
├── main.dart                      # App entry point, theme setup
├── screens/
│   └── live_stream_screen.dart   # Main UI screen for video display
└── services/
    └── rtsp_service.dart          # RTSP connection management service
```

### Key Dependencies

| Package | Purpose |
|---------|---------|
| `media_kit` | Video player framework |
| `media_kit_video` | Video widget for Flutter |
| `media_kit_libs_video` | Native video codecs |
| `http` | HTTP client for dashcam API calls |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      LiveStreamScreen                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Video Widget│  │Camera Buttons│  │   Debug Panel       │ │
│  │ (media_kit) │  │ (Front/Rear) │  │   (Connection Log)  │ │
│  └──────┬──────┘  └──────┬───────┘  └─────────────────────┘ │
│         │                  │                                 │
└─────────┼──────────────────┼─────────────────────────────────┘
          │                  │
          ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│                       RtspService                           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  • Player Management (media_kit Player)               │  │
│  │  • HTTP API Calls (enterrecorder, switchcam, etc.)    │  │
│  │  • Connection State Tracking                          │  │
│  │  • Heartbeat Timer (every 5 seconds)                  │  │
│  │  • Debug Logging                                      │  │
│  └───────────────────────────────────────────────────────┘  │
└───────────────────┬───────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
┌──────────────┐      ┌────────────────┐
│ Dashcam HTTP │      │   RTSP Stream  │
│    API       │      │  (libmpVLC)    │
│ 192.168.169.1│      │  :554/?channel=│
└──────────────┘      └────────────────┘
```

---

## Component Details

### 1. main.dart - Application Entry Point

**File:** `lib/main.dart`

**Purpose:** Initialize Flutter, MediaKit framework, and set up dark theme optimized for in-car use.

**Key Configuration:**
- Dark theme with blue accent colors
- Black background for reduced glare
- No debug banner

### 2. RtspService - Core Service Layer

**File:** `lib/services/rtsp_service.dart`

**Responsibilities:**
- Manage RTSP player lifecycle
- Handle HTTP API communication with dashcam
- Track connection state
- Send periodic heartbeats
- Provide debug logging

**Configuration Constants:**

```dart
RtspConfig
  - baseUrl: "http://192.168.169.1"
  - rtspUrl: "rtsp://192.168.169.1:554"
  - cameraChannels: ['0', '1', '2']
  - cameraNames: ['Front', 'Rear', 'PiP']
  - heartbeatInterval: 5 seconds
```

**Connection States:**
```dart
StreamConnectionStatus
  - disconnected    // No active connection
  - connecting      // Connection in progress
  - connected       // Successfully streaming
  - error           // Connection failed
```

**Key Methods:**

| Method | Lines | Purpose |
|--------|-------|---------|
| `initializePlayer()` | 84-94 | Creates new media_kit Player instance |
| `connect()` | 232-309 | Main connection method with 4-step process |
| `_enterRecorder()` | 98-122 | HTTP GET to `/app/enterrecorder` |
| `_switchCameraApi()` | 203-227 | HTTP GET to switch camera |
| `_getMediaInfo()` | 151-181 | HTTP GET to `/app/getmediainfo` |
| `_sendHeartbeat()` | 126-147 | HTTP GET heartbeat (every 5s) |
| `switchCamera()` | 330-351 | High-level camera switching |
| `disconnect()` | 312-318 | Stop player, cancel heartbeat |
| `reconnect()` | 321-327 | Disconnect and reconnect |
| `dispose()` | 354-360 | Clean up all resources |

### 3. LiveStreamScreen - UI Layer

**File:** `lib/screens/live_stream_screen.dart`

**UI Components:**

```
┌─────────────────────────────────────────────┐
│            AppBar (Dark)                     │
│  [🐛 Debug] [● Status: Connected]           │
├─────────────────────────────────────────────┤
│                                             │
│         Video Player (media_kit)            │
│                                             │
│  ┌─────────────────────────────┐           │
│  │  Stream Info: 960x540 @25fps │  ← When connected │
│  └─────────────────────────────┘           │
│                                             │
│  ┌─────────────────────────────┐           │
│  │  Debug Log Overlay          │  ← Toggleable │
│  │  [Connection steps...]      │           │
│  └─────────────────────────────┘           │
│                                             │
├─────────────────────────────────────────────┤
│  Camera Selection                            │
│  [Front] [Rear] [PiP]                        │
│  [Reconnect]                                 │
└─────────────────────────────────────────────┘
```

**State Variables:**

```dart
_selectedCameraIndex: int        // 0, 1, or 2
_isLoading: bool                  // Loading spinner state
_showDebugLog: bool               // Debug panel visibility
_errorMessage: String?            // Error to display
_videoController: VideoController? // media_kit video controller
```

---

## Flow Diagrams

### Application Initialization Flow

```
┌─────────────────────────────────────────┐
│ main()                                   │              main.dart:5
└────────────────┬────────────────────────┘
                 │
        ┌────────▼────────┐
        │ WidgetsFlutter-  │                          main.dart:7
        │ Binding.ensure-  │
        │ Initialized()    │
        └────────┬─────────┘
                 │
        ┌────────▼────────┐
        │ MediaKit.ensure- │                          main.dart:8
        │ Initialized()    │
        └────────┬─────────┘
                 │
        ┌────────▼─────────────┐
        │ DashcamPocApp (Material│                       main.dart:10
        │ App with dark theme) │
        └────────┬──────────────┘
                 │
        ┌────────▼──────────────┐
        │ LiveStreamScreen()    │                       main.dart:47
        │ (home widget)         │
        └───────────────────────┘
```

### Initial Connection Flow (RtspService.connect)

```
┌─────────────────────────────────────────┐
│ RtspService.connect()                   │          rtsp_service.dart:232
│ cameraIndex=0, skipPrerequisites=false  │
└────────────────┬────────────────────────┘
                 │
        ┌────────▼──────────┐
        │ Initialize player  │                          rtsp_service.dart:236-238
        │ if null            │
        └────────┬───────────┘
                 │
        ┌────────▼───────────────────────┐
        │ Set status = connecting        │                       rtsp_service.dart:240
        └────────┬───────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ skipPrerequisites == false?    │──Yes──┐              rtsp_service.dart:245
        └────────┬───────────────────────┘       │
                 │ No                            │
                 ▼                               │
    ┌──────────────────────────┐                │
    │ Open RTSP stream directly │                rtsp_service.dart:272-279
    │ (Skip HTTP prerequisites) │                │
    └────────┬─────────────────┘                │
             │                                  │
             └──────────────┬───────────────────┘
                            │
        ┌───────────────────▼────────────────┐
        │ Step 1: _enterRecorder() (optional) │              rtsp_service.dart:247-252
        │ GET /app/enterrecorder             │
        │ (continues if fails)               │
        └───────────────────┬────────────────┘
                            │
        ┌───────────────────▼────────────────┐
        │ Step 2: cameraIndex != 0?          │──No───┐        rtsp_service.dart:255-263
        └───────────────────┬────────────────┘       │
                            │ Yes                    │
        ┌───────────────────▼────────────────┐       │
        │ _switchCameraApi(cameraIndex)      │       │        rtsp_service.dart:257-262
        │ GET /app/setparamvalue?param=      │       │
        │ switchcam&value=X                  │       │
        └───────────────────┬────────────────┘       │
                            │                        │
                            └────────────┬──────────┘
                                         │
        ┌────────────────────────────────▼────────────────┐
        │ Step 3: _getMediaInfo() (optional)              │           rtsp_service.dart:265-270
        │ GET /app/getmediainfo                           │
        │ (uses defaults if fails)                        │
        └────────────────────────────┬───────────────────┘
                                     │
        ┌────────────────────────────▼─────────────────────┐
        │ Step 4: player.open(Media(rtsp_url))             │          rtsp_service.dart:276-280
        │ rtsp://192.168.169.1:554?channel=X               │
        └────────────────────────────┬─────────────────────┘
                                     │
        ┌────────────────────────────▼─────────────────────┐
        │ Setup stream event listeners                     │          rtsp_service.dart:283-295
        │ • completed → disconnect & stop heartbeat        │
        │ • error → set status=error                       │
        └────────────────────────────┬─────────────────────┘
                                     │
        ┌────────────────────────────▼─────────────────────┐
        │ _startHeartbeat()                                │          rtsp_service.dart:298
        │ Timer.periodic(5 seconds)                        │
        └────────────────────────────┬─────────────────────┘
                                     │
        ┌────────────────────────────▼─────────────────────┐
        │ Set status = connected                            │          rtsp_service.dart:300
        └───────────────────────────────────────────────────┘
```

### Camera Switch Flow (RtspService.switchCamera)

```
┌─────────────────────────────────────────┐
│ RtspService.switchCamera(cameraIndex)   │          rtsp_service.dart:330
└────────────────┬────────────────────────┘
                 │
        ┌────────▼────────────┐
        │ Validate cameraIndex│                           rtsp_service.dart:331-333
        │ 0 <= index < 3      │──Invalid──► THROW ERROR
        └────────┬────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ _switchCameraApi(cameraIndex)  │                     rtsp_service.dart:337-340
        │ GET /app/setparamvalue?param=  │
        │ switchcam&value=X              │
        └────────┬───────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ disconnect()                   │                       rtsp_service.dart:344
        │ • Stop heartbeat timer         │
        │ • Stop player                  │
        │ • Set status = disconnected    │
        └────────┬───────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ Future.delayed(500ms)          │                     rtsp_service.dart:347
        │ Wait for camera to switch      │
        └────────┬───────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ connect(cameraIndex: newIndex) │                     rtsp_service.dart:350
        │ Full 4-step connection process │
        └────────────────────────────────┘
```

### Heartbeat Flow

```
┌─────────────────────────────────────────┐
│ _startHeartbeat() called                │          rtsp_service.dart:184-191
└────────────────┬────────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ Timer.periodic(Duration(seconds:│                      rtsp_service.dart:186-189
        │   5), (Timer) => ...)           │
        └────────┬───────────────────────┘
                 │
         ┌───────▼──────────────────────┐ (Every 5 seconds)
         │ _sendHeartbeat()             │             rtsp_service.dart:126-147
         │ GET /app/getparamvalue?param=│
         │ rec                          │
         └───────┬──────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ Response successful?           │                         rtsp_service.dart:137-141
        └────┬───────────────────────┬───┘
             │ Yes                   │ No
    ┌────────▼────────┐     ┌────────▼────────┐
    │ Continue timer  │     │ Set status =    │
    │ (do nothing)    │     │ error           │
    └─────────────────┘     │ Stop heartbeat  │
                            └─────────────────┘
```

### Error Handling Flow

```
┌─────────────────────────────────────────┐
│ Any operation throws exception          │
└────────────────┬────────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ Catch exception in try-catch   │
        └────────┬───────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ Set _status = error             │
        │ Set _errorMessage = exception   │
        └────────┬───────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ _stopHeartbeat()               │
        │ Cancel timer if running        │
        └────────┬───────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ UI shows error overlay:        │
        │ • Error message                │
        │ • "Reconnect" button           │
        │ • "Skip HTTP Check" button     │
        │ • Debug log automatically shown│
        └────────────────────────────────┘
```

---

## Input Handling

### User Input → System Response

| User Action | UI Handler | Service Method | Result |
|-------------|------------|----------------|--------|
| App opens | `initState()` | `connect()` | Stream starts |
| Tap "Rear" | `_switchCamera(1)` | `switchCamera(1)` | Camera switches |
| Tap "Reconnect" | `_reconnect()` | `reconnect()` | Stream restarts |
| Tap debug icon | Toggle `_showDebugLog` | N/A | Show/hide log |
| Stream error | Auto | Auto-catch | Show error overlay |

### UI Event Handlers

```
┌─────────────────────────────────────────┐
│ User taps "Rear" camera button          │
└────────────────┬────────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ _switchCamera(1)               │          live_stream_screen.dart:70
        │ setState: loading=true         │
        └────────┬───────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ _rtspService.switchCamera(1)   │          live_stream_screen.dart:81
        └────────┬───────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ _videoController =             │          live_stream_screen.dart:84
        │   VideoController(_player)     │
        │ setState: loading=false        │
        └────────┬───────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ UI updates:                    │
        │ • Rear button highlighted      │
        │ • New video stream displayed   │
        └────────────────────────────────┘
```

---

## API Integration Summary

### HTTP Endpoints

| Endpoint | Method | When Called | Response Handling |
|----------|--------|-------------|-------------------|
| `/app/enterrecorder` | GET | Before connection (optional) | Continues if fails |
| `/app/setparamvalue?param=switchcam&value=X` | GET | Camera switch | Continues with warning |
| `/app/getmediainfo` | GET | Before connection (optional) | Uses defaults if fails |
| `/app/getparamvalue?param=rec` | GET | Every 5 seconds (heartbeat) | Sets error status on fail |

### RTSP Stream URLs

```
Front Camera: rtsp://192.168.169.1:554?channel=0
Rear Camera:  rtsp://192.168.169.1:554?channel=1
PiP Camera:   rtsp://192.168.169.1:554?channel=2
```

### HTTP Request Flow

```
┌─────────────────────────────────────────┐
│ _enterRecorder()                        │          rtsp_service.dart:98
└────────────────┬────────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ http.get(Uri.parse(url))       │
        │ .timeout(Duration(seconds: 5)) │
        └────────┬───────────────────────┘
                 │
        ┌────────▼───────────────────────┐
        │ statusCode == 200?             │
        └────┬───────────────────────┬───┘
             │ Yes                   │ No
    ┌────────▼────────┐     ┌────────▼────────┐
    │ Log: SUCCESS    │     │ Log: FAILED     │
    │ return true     │     │ Set errorMessage│
    │                 │     │ return false    │
    └─────────────────┘     └─────────────────┘
```

---

## File Locations Reference

| File | Path | Lines | Description |
|------|------|-------|-------------|
| Entry Point | `lib/main.dart` | 1-50 | App initialization |
| Service Layer | `lib/services/rtsp_service.dart` | 1-478 | RTSP connection management |
| UI Screen | `lib/screens/live_stream_screen.dart` | 1-452 | Video display UI |
| Dependencies | `pubspec.yaml` | 38-44 | Package dependencies |

---

## State Management

### Connection State Lifecycle

```
┌──────────┐     connect()     ┌───────────┐
│disconnected│ ───────────────▶│connecting │
└──────────┘                   └─────┬─────┘
     ▲                             │
     │                     ┌───────▼───────┐
     │                     │   connected   │
     │                     └───────┬───────┘
     │                             │
     │                    error / │
     │                    disconnect()
     │                             │
     │                    ┌───────▼───────┐
     └────────────────────│    error      │
        (reconnect)       └───────────────┘
```

### Player Lifecycle

```
┌─────────────┐
│ New Service │
└──────┬──────┘
       │ initializePlayer()
       ▼
┌─────────────┐     connect()     ┌──────────────┐
│  Player     │ ────────────────▶│  Open Stream │
│  Created    │                   │  (Media)     │
└─────────────┘                   └──────┬───────┘
                                        │
                               ┌────────▼────────┐
                               │  Playing        │
                               │  + Heartbeat    │
                               └────────┬────────┘
                                        │
                               disconnect() / error
                                        │
                               ┌────────▼────────┐
                               │  Stopped        │
                               └────────┬────────┘
                                        │
                                   dispose()
                                        │
                               ┌────────▼────────┐
                               │  Disposed       │
                               └─────────────────┘
```

---

## Debug Logging

All service operations are logged to `_connectionLog` list which can be viewed in the UI:

```
[Player initialized]
[=== Starting connection (camera: 0) ===]
[Step 1: Enter recorder (optional)...]
[Attempting enter-recorder: http://192.168.169.1/app/enterrecorder]
[Enter-recorder response: 200 - OK]
[Enter-recorder: SUCCESS]
[Step 3: Get media info (optional)...]
...
[=== Connection established ===]
[Heartbeat timer started (5s interval)]
```

---

## Quick Reference

### Connecting to Dashcam

```dart
// In LiveStreamScreen.initState()
_rtspService = RtspService(rtspUrl: widget.rtspUrl);
await _rtspService.connect(cameraIndex: 0);
```

### Switching Cameras

```dart
await _rtspService.switchCamera(1); // Switch to rear camera
```

### Handling Connection Errors

The UI automatically shows an error overlay with:
- Service error message
- Exception details
- "Reconnect" button (with HTTP checks)
- "Skip HTTP Check" button (direct RTSP)
- Debug log (automatically visible)

### Accessing Connection Log

```dart
final log = _rtspService.connectionLog;
print(log.join('\n'));
```

---

*Generated documentation for Flutter Dashcam Live Streaming POC*
