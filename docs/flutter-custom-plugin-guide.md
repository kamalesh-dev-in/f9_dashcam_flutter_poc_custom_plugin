# Flutter Custom Plugin Guide

A comprehensive guide on creating, maintaining, and publishing Flutter custom plugins — based on the `dashcam_player` plugin as a real-world reference.

---
## 17/04/2026
---
## Table of Contents

1. [What is a Custom Plugin](#what-is-a-custom-plugin)
2. [Why Create a Custom Plugin](#why-create-a-custom-plugin)
3. [Main Use Cases](#main-use-cases-of-custom-plugins)
4. [Architecture Overview](#architecture-overview)
5. [Step-by-Step: How to Create a Custom Plugin](#step-by-step-how-to-create-a-custom-plugin)
6. [Plugin Maintenance](#plugin-maintenance)
7. [Publishing a Plugin](#publishing-a-plugin)
8. [publish_to: 'none' Explained](#publish_to-none-explained)

---

## What is a Custom Plugin

A Flutter plugin is a package that provides access to native platform features (Android, iOS) from Dart code. Custom plugins are built when existing packages don't meet your needs.

Flutter runs in a sandbox — plugins are the bridge between your Dart code and the native world (hardware, OS APIs, native libraries).

---

## Why Create a Custom Plugin

| Scenario | Why a Plugin is Needed |
|---|---|
| Access hardware | Flutter can't directly talk to camera, Bluetooth, NFC, USB, sensors |
| Use native libraries | Wrap C/C++/Java/Swift libraries (FFmpeg, OpenCV, SQLite) |
| Access OS APIs | Biometrics, notifications, background tasks, file system |
| Performance-critical work | Image/video processing, audio processing, real-time rendering |
| Integrate third-party SDKs | Payment gateways, analytics, maps, ad networks |
| Share code across projects | Reusable auth flows, common components, business logic |

When no existing plugin fits, or existing ones are too heavy / abandoned / lack features — you build your own.

---

## Main Use Cases of Custom Plugins

### 1. Access Hardware
Flutter can't talk to hardware directly.
- Camera, Bluetooth, NFC, USB, Sensors
- The `dashcam_player` plugin falls here — communicating with a physical dashcam device

### 2. Use Native Libraries
Wrap existing C/C++/Java/Swift libraries for Flutter.
- FFmpeg (video), OpenCV (vision), SQLite (database)
- `dashcam_player` wraps FFmpeg for RTSP decoding

### 3. Access OS APIs
Use platform-specific features not available in Flutter.
- Android-specific: `WorkManager`, `AlarmManager`
- iOS-specific: `CoreML`, `HealthKit`

### 4. Performance-Critical Work
Move heavy operations to native for speed.
- Image/video processing, audio processing, real-time rendering
- `dashcam_player` renders directly to native surface for low latency

### 5. Integrate Third-Party SDKs
Wrap proprietary SDKs for Flutter use.
- Payment gateways (Razorpay, Stripe)
- Analytics (Firebase, Mixpanel)
- Maps (Google Maps, Mapbox)

### 6. Share Code Across Projects
Write once, reuse in multiple apps.
- Company's internal auth flow
- Common UI components with native behavior

---

## Architecture Overview

The `dashcam_player` plugin follows Flutter's standard **platform plugin** pattern with a C++ core:

```
Dart (UI + API)
  ↕ MethodChannel / EventChannel
Kotlin (Android) / Swift (iOS)
  ↕ JNI (Android) / Objective-C++ Bridge (iOS)
C++ (FFmpeg player + renderer)
```

### Layer-by-Layer Breakdown (dashcam_player reference)

#### 1. Dart Layer — `lib/`

- **`DashcamPlayerWidget`** — uses `AndroidView`/`UiKitView` (PlatformViews) to embed a native surface in the Flutter widget tree
- **`DashcamPlayerController`** — talks to native via `MethodChannel('dashcam_player')` for commands (create, connect, disconnect, switchCamera, dispose) and `EventChannel('dashcam_player/events')` for streaming status/errors/latency back to Dart
- **`DashcamConfig`** — holds F9 dashcam defaults (IP, ports, HTTP endpoints)

#### 2. Native Platform Layer (Kotlin / Swift)

- **`DashcamPlayerPlugin`** — registers the method/event channels, dispatches calls
- **`DashcamPlatformView`** — `SurfaceView` (Android) / `MTKView` (iOS) embedded as a PlatformView
- **`DashcamNativePlayer`** — the orchestration layer with a 7-step connection sequence:
  1. Ping dashcam (network check)
  2. Enter recorder mode (HTTP)
  3. Get media info (HTTP)
  4. Start heartbeat (5s interval)
  5. Start live preview (HTTP → activates RTSP)
  6. Wait for RTSP port ready
  7. Connect FFmpeg to RTSP stream

#### 3. C++ Core — `cpp/`

- **`ffmpeg_player.cpp`** — FFmpeg-based RTSP client with low-latency flags (`low_delay`, TCP transport)
- **`surface_renderer.cpp`** (Android) — renders frames via `ANativeWindow` + `swscale` → RGBA
- **Metal renderer** (iOS) — GPU-accelerated rendering via MetalKit

### Communication Flow

```
┌──────────────────────────────────────────────────────┐
│  Flutter (Dart)                                      │
│  DashcamPlayerWidget                                 │
│    → creates PlatformView (native surface)            │
│  DashcamPlayerController                             │
│    → MethodChannel:  connect(), disconnect()          │
│    ← EventChannel:   onStatusChanged, onError         │
└──────────────┬───────────────────────────────────────┘
               │ MethodChannel (command)
               │ EventChannel  (events back)
┌──────────────▼───────────────────────────────────────┐
│  Native (Kotlin / Swift)                             │
│  Plugin registers channels + PlatformView factory     │
│  NativePlayer does the real work                      │
│  Renders directly to SurfaceView / MTKView            │
└──────────────┬───────────────────────────────────────┘
               │ JNI (Android) / Obj-C++ Bridge (iOS)
┌──────────────▼───────────────────────────────────────┐
│  C/C++ Core (optional)                               │
│  Shared FFmpeg player, renderer                       │
│  Built via CMake (Android) / CocoaPods (iOS)          │
└──────────────────────────────────────────────────────┘
```

### Key Design Decisions

- **Direct native rendering** — frames go straight to SurfaceView/MTKView, bypassing Flutter's rendering pipeline for minimal latency
- **Separate heartbeat thread** — keeps the dashcam connection alive via periodic HTTP calls
- **Configurable** — `DashcamConfig` can override endpoints for different dashcam models
- **Platform consistency** — same API and connection logic on both Android and iOS

---

## Step-by-Step: How to Create a Custom Plugin

### Step 1: Create the Plugin Project

```bash
flutter create --template=plugin --platforms=android,ios dashcam_player
```

This generates:
```
dashcam_player/
├── lib/                    # Dart side
├── android/                # Kotlin/Java native
├── ios/                    # Swift/Obj-C native
├── pubspec.yaml            # Plugin config
└── example/                # Test app
```

In `pubspec.yaml`, declare platform support:
```yaml
flutter:
  plugin:
    platforms:
      android:
        package: com.dashcam.player
        pluginClass: DashcamPlayerPlugin
      ios:
        pluginClass: DashcamPlayerPlugin
```

### Step 2: Define the Dart API (`lib/`)

Create the public interface consumers will use.

**Config** (`lib/dashcam_config.dart`):
```dart
class DashcamConfig {
  final String ip;
  final int rtspPort;
  // ... with defaults + toMap() for passing to native
}
```

**Controller** (`lib/dashcam_player_controller.dart`):
```dart
class DashcamPlayerController {
  // MethodChannel — Dart → Native (commands)
  final _methodChannel = MethodChannel('dashcam_player');

  // EventChannel — Native → Dart (streaming events)
  final _eventChannel = EventChannel('dashcam_player/events');

  Future<void> connect(int cameraIndex) =>
      _methodChannel.invokeMethod('connect', {'cameraIndex': cameraIndex});

  Stream<String> get onStatusChanged =>
      _eventChannel.receiveBroadcastStream().map(/* parse */);
}
```

**Widget** (`lib/dashcam_player_widget.dart`):
```dart
class DashcamPlayerWidget extends StatefulWidget {
  // Uses PlatformView to embed native UI
  @override
  Widget build(BuildContext context) {
    return AndroidView(viewType: 'dashcam_player_view');  // Android
    // or UiKitView(viewType: '...')                       // iOS
  }
}
```

### Step 3: Android Native Implementation (`android/`)

**Plugin Registration** — `DashcamPlayerPlugin.kt`:
```kotlin
class DashcamPlayerPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var eventChannel: EventChannel

  override fun onAttachedToEngine(binding: FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "dashcam_player")
    channel.setMethodCallHandler(this)

    eventChannel = EventChannel(binding.binaryMessenger, "dashcam_player/events")
    eventChannel.setStreamHandler(MyStreamHandler())

    // Register the PlatformView
    binding.platformViewRegistry.registerViewFactory(
      "dashcam_player_view", DashcamPlatformViewFactory(binding.binaryMessenger)
    )
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "create"     -> handleCreate(call, result)
      "connect"    -> handleConnect(call, result)
      "disconnect" -> handleDisconnect(result)
      "dispose"    -> handleDispose(result)
      else -> result.notImplemented()
    }
  }
}
```

**PlatformView** — wraps a `SurfaceView`:
```kotlin
class DashcamPlatformView : PlatformView {
  private val surfaceView = SurfaceView(context)
  override fun getView(): View = surfaceView
  override fun dispose() { /* cleanup */ }
}
```

**Native Logic** — handles the actual work (HTTP calls, heartbeat, FFmpeg, etc.)

### Step 4: iOS Native Implementation (`ios/`)

Same structure, but in Swift:

**Plugin Registration**:
```swift
class DashcamPlayerPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dashcam_player", binaryMessenger: registrar.messenger())
    let instance = DashcamPlayerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // Register PlatformView
    let factory = DashcamPlatformViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: "dashcam_player_view")
  }
}
```

**PlatformView** uses `MTKView` (Metal) instead of `SurfaceView`.

### Step 5: Build Configuration

**Android** — `android/build.gradle`:
```groovy
android {
  externalNativeBuild {
    cmake {
      path "src/main/cpp/CMakeLists.txt"  // if using C/C++
    }
  }
}
```

**iOS** — `ios/dashcam_player.podspec`:
```ruby
s.dependency 'Flutter'
s.pod_target_xcconfig = { 'OTHER_LDFLAGS' => '-lstdc++' }
```

### Step 6: Test with the Example App

```bash
cd example/
flutter run
```

### The 4 Things Every Plugin Needs

| # | What | Where |
|---|------|-------|
| 1 | **Dart API** | `lib/` — Controller + Widget |
| 2 | **MethodChannel** | Same channel name on Dart + Native |
| 3 | **PlatformView** | SurfaceView (Android) / UIView (iOS) |
| 4 | **Native Implementation** | Kotlin + Swift (optional C++ core) |

---

## Plugin Maintenance

Maintenance means keeping your plugin working correctly over time.

### 1. Flutter SDK Compatibility
```yaml
environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: '>=3.10.0'
```
When Flutter releases breaking changes, your plugin must adapt or it breaks for users.

### 2. Native Dependency Updates
- **Android**: Gradle versions, `compileSdkVersion`, Kotlin version, NDK version
- **iOS**: Xcode versions, Swift version, CocoaPods deps
- **C/C++**: Library version bumps (e.g., FFmpeg)

### 3. Bug Fixes & Device Compatibility
- New Android/iOS versions may change permissions or APIs
- Different devices may behave differently
- Network edge cases (e.g., reconnection logic)

### 4. API Evolution
```dart
@Deprecated('Use connectWithConfig() instead')
Future<void> connect(int cameraIndex) => connectWithConfig(/* ... */);
```

### 5. Testing
- Unit tests for Dart logic
- Integration tests on real devices
- CI pipeline that runs on every PR

---

## Publishing a Plugin

### Option A: Publish to pub.dev (Public, Free)

```bash
# Dry run — check for issues
flutter pub publish --dry-run

# Publish for real
flutter pub publish
```

Required in `pubspec.yaml`:
```yaml
name: dashcam_player
description: Flutter plugin for F9 dashcam live streaming via RTSP
version: 1.0.0
homepage: https://github.com/yourname/dashcam_player

environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: '>=3.10.0'
```

**Prerequisites:**
- A Google account (pub.dev uses it for auth)
- First publish: `flutter pub pub login` opens browser for OAuth

**pub.dev Scoring:**

| Check | What it wants |
|-------|--------------|
| `README.md` | Usage docs + examples |
| `CHANGELOG.md` | Version history |
| `LICENSE` | Open source license |
| Platform support | Declared in pubspec |
| Example app | Working `example/` folder |
| Scores | 0–130 points (health, maintenance, popularity) |

### Option B: Private / Internal (Git-based)

**Git dependency:**
```yaml
dependencies:
  dashcam_player:
    git:
      url: https://github.com/yourcompany/dashcam_player.git
      ref: v1.0.0
```

**Path dependency (monorepo):**
```yaml
dependencies:
  dashcam_player:
    path: ../packages/dashcam_player
```

**Private pub server:**
```bash
flutter pub publish --server https://your-private-pub-server.com
```

### Option C: Unpublish

```bash
# Retract within 7 days
flutter pub pub retract dashcam_player 1.0.0

# Fully remove (only if no dependents)
flutter pub pub unpublish dashcam_player 1.0.0
```

### Pre-Publish Checklist

```
✅ pubspec.yaml — name, version, description, homepage, SDK constraints
✅ README.md — install instructions, usage example, screenshots
✅ CHANGELOG.md — what changed in this version
✅ LICENSE — MIT / Apache 2.0 / BSD
✅ example/ — working demo app
✅ flutter pub publish --dry-run passes with no errors
✅ Tested on both Android + iOS real devices
✅ API is stable — no breaking changes planned soon
```

---

## publish_to: 'none' Explained

This line in `pubspec.yaml` prevents the package from being published to pub.dev:

```yaml
publish_to: 'none'
```

### Why it exists
- **Private/internal packages** — proprietary code that shouldn't be public
- **Monorepo sub-packages** — consumed via path dependency, not pub.dev
- **Prevent accidental publish** — safety net so `flutter pub publish` fails immediately

### When to remove it
Only remove when you're ready to publish publicly — replace with a `homepage` URL instead.

### When to use it
- Proprietary or company-internal plugins
- Project-specific integrations
- Plugins too specific for general use
