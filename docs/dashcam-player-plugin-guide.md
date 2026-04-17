# Dashcam Player Plugin — Complete Technical Guide

## Table of Contents

1. [Pipeline Flow Diagram](#1-pipeline-flow-diagram)
2. [Plugin Purpose](#2-plugin-purpose)
3. [Architecture Overview](#3-architecture-overview)
4. [Connection Protocol](#4-connection-protocol)
5. [FFmpeg Decoding Pipeline](#5-ffmpeg-decoding-pipeline)
6. [Native Rendering](#6-native-rendering)
7. [Flutter to Native Bridge](#7-flutter-to-native-bridge)
8. [Android Implementation](#8-android-implementation)
9. [iOS Implementation](#9-ios-implementation)
10. [Obj-C++ Bridge Deep Dive](#10-obj-c-bridge-deep-dive)
11. [PlatformView Deep Dive](#11-platformview-deep-dive)
12. [Android vs iOS Comparison](#12-android-vs-ios-comparison)
13. [Developer Config Guide — Using With Different Dashcams](#13-developer-config-guide--using-with-different-dashcams)
14. [Session History](#14-session-history)

---

## 1. Pipeline Flow Diagram

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║                                                                                  ║
║   DASHCAM PLAYER PLUGIN — CONNECTION & STREAMING PIPELINE                        ║
║                                                                                  ║
║   ┌────────────────────────────────────────────────────────────────┐              ║
║   │ FLUTTER LAYER                                                 │              ║
║   │                                                                │              ║
║   │  ┌──────────────────────────────────────────────────────┐      │              ║
║   │  │ Build PlatformView                                     │      │              ║
║   │  │ Android → SurfaceView  |  iOS → MTKView (Metal)      │      │              ║
║   │  │ onPlatformViewCreated(viewId)                         │      │              ║
║   │  └────────────────────────┬─────────────────────────────┘      │              ║
║   │                           │                                    │              ║
║   │  ┌────────────────────────▼─────────────────────────────┐      │              ║
║   │  │ controller.create(viewId)                             │      │              ║
║   │  │ MethodChannel → native: lookup PlatformView by viewId│      │              ║
║   │  │ Create FFmpegPlayer + Renderer, link to surface      │      │              ║
║   │  │ Return playerId to Dart                               │      │              ║
║   │  └────────────────────────┬─────────────────────────────┘      │              ║
║   │                           │                                    │              ║
║   │  ┌────────────────────────▼─────────────────────────────┐      │              ║
║   │  │ controller.connect(cameraIndex: 0|1|2)                │      │              ║
║   │  │ MethodChannel → native: begin 7-step sequence         │      │              ║
║   │  └────────────────────────┬─────────────────────────────┘      │              ║
║   └───────────────────────────┼────────────────────────────────────┘              ║
║                               │                                                  ║
║  ┌────────────────────────────▼────────────────────────────────────┐              ║
║  │ NATIVE PLAYER (Kotlin / Swift) — runs on background thread     │              ║
║  │                                                                  │              ║
║  │  ┌─────────────────────────────────────────────────────────┐    │              ║
║  │  │ STEP 0: Ping dashcam                                     │    │              ║
║  │  │ GET http://192.168.169.1/app/getparamvalue?param=rec     │    │              ║
║  │  │ timeout: 3s | non-critical, continue on failure          │    │              ║
║  │  └─────────────────────────┬───────────────────────────────┘    │              ║
║  │                            │                                    │              ║
║  │  ┌─────────────────────────▼───────────────────────────────┐    │              ║
║  │  │ STEP 1: Enter recorder mode                              │    │              ║
║  │  │ GET http://192.168.169.1/app/enterrecorder               │    │              ║
║  │  │ timeout: 2s | non-critical                               │    │              ║
║  │  └─────────────────────────┬───────────────────────────────┘    │              ║
║  │                            │                                    │              ║
║  │  ┌─────────────────────────▼───────────────────────────────┐    │              ║
║  │  │ STEP 2: Get media info                                   │    │              ║
║  │  │ GET http://192.168.169.1/app/getmediainfo                │    │              ║
║  │  │ timeout: 2s | non-critical, always returns true          │    │              ║
║  │  └─────────────────────────┬───────────────────────────────┘    │              ║
║  │                            │                                    │              ║
║  │  ┌─────────────────────────▼───────────────────────────────┐    │              ║
║  │  │ STEP 3: Start heartbeat                                  │    │              ║
║  │  │ GET http://192.168.169.1/app/getparamvalue?param=rec     │    │              ║
║  │  │ every 5s for connection keepalive                        │    │              ║
║  │  └─────────────────────────┬───────────────────────────────┘    │              ║
║  │                            │                                    │              ║
║  │  ┌─────────────────────────▼───────────────────────────────┐    │              ║
║  │  │ STEP 4: Activate RTSP stream ★ CRITICAL                  │    │              ║
║  │  │ GET http://192.168.169.1/?custom=1&cmd=2015&par={0|1|2}  │    │              ║
║  │  │ cameraIndex: 0=Front, 1=Rear, 2=PiP                     │    │              ║
║  │  └─────────────────────────┬───────────────────────────────┘    │              ║
║  │                            │                                    │              ║
║  │  ┌─────────────────────────▼───────────────────────────────┐    │              ║
║  │  │ STEP 5: Wait for RTSP port ready                         │    │              ║
║  │  │ TCP probe 192.168.169.1:554 every 300ms                  │    │              ║
║  │  │ timeout: 5000ms total                                    │    │              ║
║  │  └─────────────────────────┬───────────────────────────────┘    │              ║
║  │                            │                                    │              ║
║  │  ┌─────────────────────────▼───────────────────────────────┐    │              ║
║  │  │ STEP 6: Verify FFmpeg native libraries                   │    │              ║
║  │  │ nativeTest() must return "working"                       │    │              ║
║  │  │ If STUB mode → permanent error, abort                    │    │              ║
║  │  └─────────────────────────┬───────────────────────────────┘    │              ║
║  │                            │                                    │              ║
║  │  ┌─────────────────────────▼───────────────────────────────┐    │              ║
║  │  │ STEP 7: FFmpeg RTSP connect (inner 3-retry)              │    │              ║
║  │  │ Open rtsp://192.168.169.1:554/ with TCP transport        │    │              ║
║  │  │ Flags: low_delay, ignore_err, genpts+igndts              │    │              ║
║  │  │ 3 attempts, 1s delay between                             │    │              ║
║  │  └─────────────────────────┬───────────────────────────────┘    │              ║
║  │                            │                                    │              ║
║  │             ┌──────────────▼──────────────┐                     │              ║
║  │             │ All 7 steps succeeded?       │                     │              ║
║  │             └──────┬──────────────┬────────┘                     │              ║
║  │                    │ Yes          │ No                           │              ║
║  │                    │              │                              │              ║
║  │                    │       ┌──────▼──────────────────┐          │              ║
║  │                    │       │ Stop heartbeat           │          │              ║
║  │                    │       │ Wait 3s (check cancel    │          │              ║
║  │                    │       │   every 0.5s)            │          │              ║
║  │                    │       │ Retry from Step 0 ───────┼──►loop   │              ║
║  │                    │       └─────────────────────────┘          │              ║
║  │                    │                                            │              ║
║  │  ┌─────────────────▼──────────────────────────────────┐        │              ║
║  │  │ nativeStart() — spawn decode thread                 │        │              ║
║  │  │ EventChannel → Dart: "Playing"                      │        │              ║
║  │  └─────────────────┬──────────────────────────────────┘        │              ║
║  └────────────────────┼───────────────────────────────────────────┘              ║
║                       │                                                          ║
║  ┌────────────────────▼───────────────────────────────────────────┐              ║
║  │ FFMPEG DECODE THREAD (C++ pthread, background)                 │              ║
║  │                                                                  │              ║
║  │  ┌─────────────────────────────────────────────────────────┐    │              ║
║  │  │ Loop while is_playing:                                   │    │              ║
║  │  │                                                          │    │              ║
║  │  │   av_read_frame(format_ctx, packet)                      │    │              ║
║  │  │        │                                                 │    │              ║
║  │  │        ▼                                                 │    │              ║
║  │  │   packet is video stream? ──No──► av_packet_unref, loop  │    │              ║
║  │  │        │ Yes                                             │    │              ║
║  │  │        ▼                                                 │    │              ║
║  │  │   avcodec_send_packet(codec_ctx, packet)                 │    │              ║
║  │  │        │                                                 │    │              ║
║  │  │        ▼                                                 │    │              ║
║  │  │   avcodec_receive_frame(codec_ctx, frame)                │    │              ║
║  │  │        │                                                 │    │              ║
║  │  │        ▼                                                 │    │              ║
║  │  │   sws_scale: YUV → RGBA (Android) | BGRA (iOS)          │    │              ║
║  │  │        │  SWS_FAST_BILINEAR, 32-byte aligned buffer      │    │              ║
║  │  │        │  Android: AV_PIX_FMT_RGBA                       │    │              ║
║  │  │        │  iOS: AV_PIX_FMT_BGRA (fixes blue tint)         │    │              ║
║  │  │        ▼                                                 │    │              ║
║  │  │   platform_renderer_render_frame(renderer, frame)        │    │              ║
║  │  │        │                                                 │    │              ║
║  │  │        ▼                                                 │    │              ║
║  │  │   usleep(10000) — 10ms sleep to prevent CPU spin         │    │              ║
║  │  │        │                                                 │    │              ║
║  │  │        └──► loop                                         │    │              ║
║  │  └─────────────────────────────────────────────────────────┘    │              ║
║  └────────────────────┬───────────────────────────────────────────┘              ║
║                       │                                                          ║
║  ┌────────────────────▼───────────────────────────────────────────┐              ║
║  │ NATIVE RENDERING (platform-specific, display-synced)           │              ║
║  │                                                                  │              ║
║  │  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐ │              ║
║  │  │  ANDROID PATH (CPU blit)                                  │ │              ║
║  │  │                                                           │ │              ║
║  │  │  ANativeWindow_lock(window, &buffer)                      │ │              ║
║  │  │        │                                                  │ │              ║
║  │  │        ▼                                                  │ │              ║
║  │  │  memcpy: RGBA → ANativeWindow buffer (row-by-row)         │ │              ║
║  │  │        │                                                  │ │              ║
║  │  │        ▼                                                  │ │              ║
║  │  │  ANativeWindow_unlockAndPost() → vsync → screen           │ │              ║
║  │  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘ │              ║
║  │                                                                  │              ║
║  │  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐ │              ║
║  │  │  iOS PATH (Metal GPU pipeline)                            │ │              ║
║  │  │                                                           │ │              ║
║  │  │  MTLTexture.replaceRegion(BGRA pixels)                    │ │              ║
║  │  │  pixel format: MTLPixelFormatBGRA8Unorm                   │ │              ║
║  │  │        │                                                  │ │              ║
║  │  │        ▼                                                  │ │              ║
║  │  │  dispatch_async(main) { mtkView.setNeedsDisplay() }       │ │              ║
║  │  │        │                                                  │ │              ║
║  │  │        ▼                                                  │ │              ║
║  │  │  MTKViewDelegate.draw(in:) — vsync callback               │ │              ║
║  │  │        │                                                  │ │              ║
║  │  │        ▼                                                  │ │              ║
║  │  │  Metal command buffer:                                    │ │              ║
║  │  │    bind texture → draw 4-vertex triangle strip quad       │ │              ║
║  │  │    presentDrawable → commit → screen                      │ │              ║
║  │  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘ │              ║
║  └──────────────────────────────────────────────────────────────────┘              ║
║                                                                                  ║
║  ┌──────────────────────────────────────────────────────────────────┐              ║
║  │ CAMERA SWITCHING (triggered from Dart)                           │              ║
║  │                                                                  │              ║
║  │  nativeStop() → stop current playback                            │              ║
║  │        │                                                         │              ║
║  │        ▼                                                         │              ║
║  │  GET http://192.168.169.1/app/setparamvalue?param=switchcam       │              ║
║  │      &value={0=Front, 1=Rear, 2=PiP}                             │              ║
║  │        │                                                         │              ║
║  │        ▼                                                         │              ║
║  │  Wait 500ms → probe RTSP port 554 (5s timeout)                   │              ║
║  │        │                                                         │              ║
║  │        ▼                                                         │              ║
║  │  nativeConnect(rtsp://192.168.169.1:554/) → infinite retry       │              ║
║  │        │  every 3s, check cancellation every 0.5s                │              ║
║  │        ▼                                                         │              ║
║  │  nativeStart() → resume decode thread                            │              ║
║  └──────────────────────────────────────────────────────────────────┘              ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

---

## 2. Plugin Purpose

The `dashcam_player` plugin is a custom Flutter plugin built for **low-latency live video streaming from an F9 dashcam** over RTSP. It is NOT a generic video player.

### Why a Custom Plugin?

Standard Flutter video players (video_player, chewie) add too much latency for a real-time dashcam feed. This plugin:
- Uses **FFmpeg directly in C++** for RTSP decoding (no high-level player abstractions)
- Renders via **native surfaces** (Android SurfaceView / iOS MTKView) — not Flutter's compositor
- Implements the **dashcam's proprietary HTTP API** (connection sequence, heartbeat, camera switching)
- Hardcodes F9-specific settings: IP `192.168.169.1`, HTTP port 80, RTSP port 554

### What It Connects To

The F9 dashcam creates a Wi-Fi hotspot. The phone connects to this network, then:
- HTTP calls activate and control the stream
- FFmpeg pulls the live RTSP video feed
- Native surfaces render with minimal latency

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────┐
│  Flutter App (live_stream_screen.dart)      │
│  ┌─────────────────────────────────────────┐│
│  │  DashcamPlayerWidget (PlatformView)     ││
│  │  DashcamPlayerController                ││
│  └──────────────┬──────────────────────────┘│
└─────────────────┼────────────────────────────┘
        │ MethodChannel / EventChannel
        ▼
┌─────────────────────────────────────────────┐
│  Native Plugin Layer                        │
│  ┌──────────────┐   ┌──────────────────┐    │
│  │  Android      │   │  iOS             │    │
│  │  Kotlin + JNI │   │  Swift + Obj-C++ │    │
│  │       │       │   │       │          │    │
│  │  ┌────▼────┐  │   │  ┌────▼─────┐   │    │
│  │  │ C++     │  │   │  │ C++      │   │    │
│  │  │ FFmpeg  │  │   │  │ FFmpeg   │   │    │
│  │  └────┬────┘  │   │  └────┬─────┘   │    │
│  │  SurfaceView   │   │  Metal/MTKView  │    │
│  └──────────────┘   └──────────────────┘    │
└─────────────────────────────────────────────┘
        │
        ▼
   F9 Dashcam (RTSP + HTTP API)
```

### Three Communication Channels

| Channel | Type | Purpose |
|---------|------|---------|
| `dashcam_player` | MethodChannel | Commands (create, connect, disconnect, switchCamera, dispose) |
| `dashcam_player/events` | EventChannel | Status updates, errors, latency measurements |
| `dashcam_player_view` | PlatformView | Native video surface embedded in Flutter widget tree |

---

## 4. Connection Protocol

### Network Configuration

- **IP Address**: `192.168.169.1`
- **RTSP Port**: 554
- **HTTP Port**: 80
- **RTSP URL**: `rtsp://192.168.169.1:554/` (plain URL — no paths or query params)
- **User-Agent**: `"HiCamera"`

### The 7-Step Connection Sequence

Both Android and iOS follow the same 7 steps:

| Step | Action | Endpoint / Method | Timeout | Critical? |
|------|--------|-------------------|---------|-----------|
| 0 | Ping connectivity | `GET /app/getparamvalue?param=rec` | 3s | No |
| 1 | Enter recorder mode | `GET /app/enterrecorder` | 2s | No |
| 2 | Get media info | `GET /app/getmediainfo` | 2s | No |
| 3 | Start heartbeat | `GET /app/getparamvalue?param=rec` every 5s | 2s | Ongoing |
| 4 | Activate stream | `GET /?custom=1&cmd=2015&par={camera}` | 2s | **Yes** — triggers RTSP |
| 5 | Wait for RTSP port | TCP connect to `192.168.169.1:554`, poll every 300ms | 5s total | Yes |
| 6 | Verify FFmpeg | Native test call | — | Yes |
| 7 | RTSP connect | `ffmpeg open rtsp://192.168.169.1:554/` (TCP) | 3 retries, 1s apart | Yes |

**Steps 0-2 are treated as non-critical** — failures are logged but the sequence continues.
**Step 4 is the critical trigger** — without it, the dashcam doesn't start the RTSP stream.
**TCP transport only** — UDP doesn't work reliably with this dashcam.
**RTSP URL is plain** `rtsp://192.168.169.1:554/` — the dashcam ignores paths/query params.

### Heartbeat Mechanism

- Hits `GET /app/getparamvalue?param=rec` every **5 seconds**
- Keeps the dashcam from closing the connection
- Stops when player is released or disconnected

### Camera Switching

1. Stop current playback
2. Call `GET /app/setparamvalue?param=switchcam&value={0|1|2}` (0=Front, 1=Rear, 2=PiP)
3. Wait 500ms for stream restart
4. Poll RTSP port readiness (5s timeout)
5. Reconnect RTSP with infinite retries

Camera switching does NOT redo the 7-step sequence — the dashcam is already in recorder mode.

### Retry Strategy

- **Full connection**: Infinite retries, 3-second delay between attempts, checking cancellation every 0.5s
- **RTSP connect**: 3 attempts per cycle, 1-second delay between
- **Camera switch reconnect**: Infinite retries, 3-second delay
- Logging: First 3 attempts log everything, then only every 5th attempt

---

## 5. FFmpeg Decoding Pipeline

### Pipeline Flow

```
RTSP Stream → av_read_frame() → avcodec_send_packet() → avcodec_receive_frame() → sws_scale() → Platform Renderer
     ↑                                                                                                  ↓
  Background Thread (pthread)                                                                    Android: SurfaceView
                                                                                                 iOS: Metal MTKView
```

### RTSP Connection Setup (Low-Latency Flags)

```cpp
AVDictionary* options = nullptr;
av_dict_set(&options, "rtsp_transport", "tcp", 0);       // TCP only (dashcam requirement)
av_dict_set(&options, "err_detect", "ignore_err", 0);    // Tolerate F9 dashcam codec quirks
av_dict_set(&options, "fflags", "+genpts+igndts", 0);    // Generate PTS, ignore DTS
av_dict_set(&options, "flags", "low_delay", 0);          // Minimize buffering
```

**Why each flag:**
- `ignore_err` — The F9 dashcam produces occasionally corrupt frames; this prevents the stream from dying
- `genpts+igndts` — The dashcam's timestamps can be wrong; FFmpeg regenerates them
- `low_delay` — Disables FFmpeg's internal frame buffering
- `tcp` — Dashcam doesn't handle UDP reliably

### Decoding Loop

Runs on a **single background pthread**:
1. `av_read_frame()` — Pulls a packet from RTSP
2. `avcodec_send_packet()` — Feeds it to the decoder
3. `avcodec_receive_frame()` — Gets decoded YUV frame
4. `sws_scale()` — Converts pixel format
5. `platform_renderer_render_frame()` — Sends to native renderer
6. 10ms sleep to prevent CPU hogging

### Codec Selection

Pure **software decoding** — no hardware acceleration. FFmpeg auto-selects the decoder based on the stream's codec ID (likely H.264 from the dashcam).

### YUV to RGB Conversion

| Platform | Input | Output | Alignment |
|----------|-------|--------|-----------|
| Android | YUV (from decoder) | RGBA_8888 | 32-byte aligned for SIMD |
| iOS | YUV (from decoder) | BGRA (Metal byte order) | 32-byte aligned |

Uses `sws_scale()` with `SWS_FAST_BILINEAR` — fast but slightly lower quality, appropriate for a live feed.

### Threading Model

```
Main Thread          Background Thread (pthread)
──────────           ──────────────────────────
Flutter UI           av_read_frame()
Platform calls       avcodec_send/receive()
                     sws_scale()
                     render_frame()
                         │
                     mutex synchronization
                         │
                     ←───┘  (frame delivery)
```

- Single mutex protects FFmpeg operations
- Synchronous frame-by-frame rendering (no frame queue)
- Pre-allocated buffers (no malloc during playback)

### Error Handling

- Errors break the decoding loop and stop playback
- No automatic reconnection at the C++ level — handled by Kotlin/Swift retry logic
- Clean resource cleanup on all error paths (av_frame_free, av_packet_free, avcodec_close)

### Key Takeaway

The pipeline is intentionally **simple and synchronous** — no frame queue, no hardware acceleration, no multi-threaded decoding. This trades throughput for predictability and lowest possible latency.

---

## 6. Native Rendering

### Android: ANativeWindow + SurfaceView

**Surface acquisition:**
1. `SurfaceView` created in `DashcamPlatformView`
2. `SurfaceHolder.Callback.surfaceCreated()` triggers native init
3. `ANativeWindow_fromSurface()` extracts the native window
4. Buffer format set to `RGBA_8888`

**Per-frame rendering:**
```
FFmpeg YUV frame
  → sws_scale() converts YUV → RGBA (32-byte aligned)
  → ANativeWindow_lock() acquires buffer
  → memcpy row-by-row into window buffer
  → ANativeWindow_unlockAndPost() presents (implicitly vsync'd)
```

sws_scale context is reused across frames (same dimensions). RGB buffer pre-allocated with `av_malloc` (32-byte SIMD alignment). 10ms sleep in playback thread prevents CPU spinning.

### iOS: Metal + MTKView

**Pipeline setup:**
1. `MTKView` created with `isPaused = true`, `enableSetNeedsDisplay = true`
2. Metal device + command queue created from the view
3. Inline shaders compiled from embedded C string (no separate .metal files)

**Metal Shaders (embedded in C++):**
- **Vertex shader**: Full-screen triangle strip quad (4 vertices, -1 to 1 NDC)
- **Fragment shader**: Linear-sampled texture lookup — direct passthrough, no color transforms

**Per-frame rendering (two threads):**
```
Background thread (FFmpeg):
  sws_scale() YUV → BGRA (Metal byte order, fixes blue tint)
  MTLTexture.replaceRegion() uploads BGRA data
  frameReady = true
  dispatch_async(main) { mtkView.setNeedsDisplay() }

Main thread (MTKView delegate):
  metal_renderer_draw()
  → Get current drawable
  → Create command buffer + render pass (black clear)
  → Bind texture, draw 4-vertex triangle strip
  → Present drawable, commit
```

**Key details:**
- BGRA format chosen specifically for iOS Metal byte order (comment: "fixes blue tint")
- Texture reused when dimensions don't change
- `isPaused = true` means we control when to draw manually via `setNeedsDisplay()`
- Rendering is display-synced through MTKView's vsync

### What's Notably Absent

- **No frame dropping logic** — every decoded frame is rendered
- **No double buffering** — each frame overwrites the previous one directly
- **No hardware-accelerated decode** — both platforms use FFmpeg software decoding

---

## 7. Flutter to Native Bridge

### MethodChannel API (`dashcam_player`)

| Method | Parameters | Returns | Purpose |
|--------|-----------|---------|---------|
| `create` | `{viewId: int}` | `playerId: int` | Links controller to a PlatformView |
| `connect` | `{playerId, cameraIndex}` | `bool` | Starts RTSP streaming |
| `disconnect` | `{playerId}` | `void` | Stops playback |
| `switchCamera` | `{playerId, cameraIndex}` | `bool` | Switches camera (0/1/2) |
| `dispose` | `{playerId}` | `void` | Releases native resources |

### EventChannel Events (`dashcam_player/events`)

All events are structured as `{type, data}`:

```
{"type": "statusChanged",         "data": {"message": "Connecting..."}}
{"type": "error",                 "data": {"message": "Connection failed"}}
{"type": "videoRenderingStarted", "data": {"latencyMs": 120}}
{"type": "prepared",              "data": null}
```

Dart demuxes by type into separate `StreamController`s: `onStatusChanged`, `onError`, `onLatencyMeasured`, `onPrepared`.

### PlatformView Linking

The **viewId** bridges the controller to the native surface:

```
1. Widget builds → Flutter creates PlatformView → calls onPlatformViewCreated(viewId)
2. Widget calls controller.create(viewId) via MethodChannel
3. Native plugin looks up PlatformView by viewId from registry
4. Extracts SurfaceView/MTKView from PlatformView
5. Creates native player, links it to that surface
6. Returns playerId to Dart for future calls
```

Both platforms maintain registries: `Map<Int, PlatformView>` and `Map<Int, NativePlayer>`.

### Complete "connect" Trace

```
Dart UI (button press)
  │
  ▼
controller.create(viewId)          ← MethodChannel
  │  Native: lookup PlatformView, create DashcamNativePlayer, link surface
  ▼
controller.connect(cameraIndex:0)  ← MethodChannel
  │  Native: 7-step connection sequence on IO thread
  │
  │  ┌─── Events flow back ───┐
  │  │ "statusChanged: Connecting..."  → UI shows spinner
  │  │ "statusChanged: Playing"        → UI hides spinner
  │  │ "videoRenderingStarted: 120ms"  → UI shows latency badge
  │  └────────────────────────────────┘
  ▼
FFmpeg decodes → renders directly to PlatformView surface
```

### Threading Model

| Platform | MethodChannel calls | EventChannel sends |
|----------|-------------------|-------------------|
| Android | IO thread via `handler.post()` | Main thread via `Handler(Looper.getMainLooper())` |
| iOS | Main thread | Main thread via `DispatchQueue.main.async` |

---

## 8. Android Implementation

### File Structure

```
packages/dashcam_player/android/
├── build.gradle                              # Build config
├── src/main/
│   ├── AndroidManifest.xml                   # App manifest
│   ├── jniLibs/                              # Prebuilt FFmpeg .so libraries
│   │   ├── arm64-v8a/                        # 64-bit ARM
│   │   └── armeabi-v7a/                      # 32-bit ARM
│   ├── cpp/                                  # C++ native code
│   │   ├── CMakeLists.txt                    # CMake build
│   │   ├── include/                          # FFmpeg headers
│   │   ├── ffmpeg_player.h / .cpp            # FFmpeg RTSP player
│   │   ├── jni_bridge.h / .cpp              # JNI bridge
│   │   └── surface_renderer.h / .cpp        # Surface rendering
│   └── kotlin/com/dashcam/player/
│       ├── DashcamPlayerPlugin.kt            # Plugin entry point
│       ├── DashcamNativePlayer.kt            # Player logic
│       ├── DashcamPlatformView.kt            # Flutter view wrapper
│       ├── DashcamPlatformViewFactory.kt     # View factory
│       ├── NativeFFmpegPlayer.kt             # JNI interface
│       └── DashcamConfig.kt                  # Constants
```

### Languages Used

| Language | Where | Why |
|----------|-------|-----|
| **Gradle** | `build.gradle` | Android standard build system; configures SDK, CMake, dependencies |
| **Kotlin** | 6 `.kt` files | Flutter's recommended language for Android plugins; coroutines for async work |
| **C++** | 3 `.cpp` files | FFmpeg is a C library — must interface via C/C++ for RTSP decoding |
| **CMake** | `CMakeLists.txt` | Builds the C++ shared library (`.so`) that Kotlin calls via JNI |
| **XML** | `AndroidManifest.xml` | Standard Android manifest (minimal — no extra permissions needed) |

### File-by-File Breakdown

#### `DashcamConfig.kt` — Configuration Constants

**Language:** Kotlin | **Type:** `object` (singleton)

Holds all dashcam-specific constants:
- `DASHCAM_IP = "192.168.169.1"` — the dashcam's Wi-Fi hotspot IP
- `RTSP_PORT = 554`, `HTTP_PORT = 80`
- `RTSP_URL = "rtsp://192.168.169.1:554/"`
- Camera indices: `FRONT = 0`, `REAR = 1`, `PIP = 2`
- HTTP API endpoints: `/app/enterrecorder`, `/app/setparamvalue`, `/app/getparamvalue`

**Why a separate file:** Keeps all hardcoded dashcam values in one place. If the dashcam model changes, you only edit this file.

---

#### `DashcamPlayerPlugin.kt` — Plugin Entry Point

**Language:** Kotlin | **Role:** Flutter's single entry point to the native code

**Key methods:**
| Method | Purpose |
|--------|---------|
| `onAttachedToEngine()` | Registers MethodChannel, EventChannel, and PlatformView factory |
| `onMethodCall()` | Routes incoming Dart calls: `create`, `connect`, `disconnect`, `switchCamera`, `dispose` |
| `handleCreate()` | Looks up PlatformView by viewId, creates a `DashcamNativePlayer`, links the SurfaceView |
| `sendEvent()` | Sends events to Dart via EventChannel on the main thread |
| `onDetachedFromEngine()` | Cleans up all players and channels |

**Registries maintained:**
- `playerRegistry: MutableMap<Int, DashcamNativePlayer>` — maps playerId to native player
- Each `DashcamPlatformView` registers itself in a static map by viewId

---

#### `DashcamNativePlayer.kt` — Player Logic

**Language:** Kotlin | **Role:** Core business logic — 7-step connection, heartbeat, camera switching

**Key methods:**
| Method | What it does |
|--------|-------------|
| `connect(cameraIndex)` | Runs the 7-step connection sequence using Kotlin coroutines |
| `disconnect()` | Stops heartbeat, stops native player |
| `switchCamera(cameraIndex)` | HTTP API call + RTSP reconnect |
| `startHeartbeat()` | GET request every 5 seconds to keep dashcam alive |
| `httpGet(url)` | Synchronous HTTP call with 2-3s timeout via `HttpURLConnection` |
| `waitForRtspPort()` | Polls TCP port 554 until ready (5s timeout) |
| `connectWithRetry()` | RTSP connect with 3 retries, 1s delay between |

**Why Kotlin coroutines:** HTTP calls to the dashcam are blocking. Coroutines let us run them on an IO dispatcher without freezing the UI thread, while keeping the code readable with sequential `suspend` functions.

---

#### `NativeFFmpegPlayer.kt` — JNI Bridge (Kotlin side)

**Language:** Kotlin | **Role:** Declares `external` native methods implemented in C++

**Key methods:**
| Method | JNI target |
|--------|-----------|
| `nativeTest(): String` | Verifies FFmpeg libraries are loaded |
| `nativeCreate(surface): Long` | Creates C++ FFmpegPlayer, returns pointer as Long |
| `nativeConnect(ptr, url): Boolean` | Opens RTSP connection |
| `nativeStart(ptr)` | Starts decoding thread |
| `nativeStop(ptr)` | Stops decoding thread |
| `nativeRelease(ptr)` | Frees all C++ resources |

Loads native library: `System.loadLibrary("dashcamplayer")`

**Why:** Kotlin cannot call C++ directly. This class is the JNI contract — Kotlin calls these methods, and C++ `jni_bridge.cpp` implements them. The `Long` return value is a memory pointer to the C++ object.

---

#### `DashcamPlatformView.kt` — Flutter View Wrapper

**Language:** Kotlin | **Role:** Wraps an Android `SurfaceView` for Flutter embedding

- Creates a `SurfaceView` and keeps screen on
- Static registry: `companion object { val views = mutableMapOf<Int, DashcamPlatformView>() }`
- `getView()` returns the SurfaceView to Flutter's engine

**Why SurfaceView:** Provides direct pixel access via `ANativeWindow` — bypassing Flutter's rendering pipeline for zero-additional-latency video display.

---

#### `DashcamPlatformViewFactory.kt` — View Factory

**Language:** Kotlin | **Role:** Simple factory Flutter calls to create PlatformViews

```kotlin
class DashcamPlatformViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return DashcamPlatformView(context, viewId)
    }
}
```

**Why:** Flutter's platform view API requires a factory pattern. When Dart builds `AndroidView(viewType: 'dashcam_player_view')`, Flutter calls this factory.

---

#### `ffmpeg_player.cpp` — FFmpeg RTSP Player (C++ Core)

**Language:** C++ | **Role:** The actual RTSP client and video decoder

**Key functions:**
| Function | What it does |
|----------|-------------|
| `ffmpeg_player_create()` | Allocates FFmpegPlayer struct, initializes mutex |
| `ffmpeg_player_connect()` | Opens RTSP with low-latency flags, finds video stream, opens codec |
| `ffmpeg_player_start()` | Spawns background `pthread` for decoding loop |
| `playback_thread()` | Loop: `av_read_frame` → `avcodec_send_packet` → `avcodec_receive_frame` → render |
| `ffmpeg_player_stop()` | Sets `is_playing = false`, joins thread |
| `ffmpeg_player_release()` | Frees codec context, format context, mutex |

**Why C++:** FFmpeg is a C library with no Java/Kotlin bindings. C++ gives direct access to `libavformat` (RTSP), `libavcodec` (decoding), and `libswscale` (color conversion) with minimal overhead.

---

#### `jni_bridge.cpp` — JNI Bridge (C++ side)

**Language:** C++ | **Role:** Implements the `external` methods declared in `NativeFFmpegPlayer.kt`

```cpp
Java_com_dashcam_player_NativeFFmpegPlayer_nativeCreate(...)
    → Creates FFmpegPlayer, sets surface, returns pointer as jlong
```

**Why:** JNI is the only way Java/Kotlin can call C++. The `jlong` (64-bit int) stores the C++ pointer — Kotlin passes it back on every call so C++ knows which player instance to use.

---

#### `surface_renderer.cpp` — Frame-to-Surface Renderer

**Language:** C++ | **Role:** Converts decoded FFmpeg frames and writes them to the Android SurfaceView

**Key functions:**
| Function | What it does |
|----------|-------------|
| `surface_renderer_create()` | Allocates SurfaceRenderer struct |
| `surface_renderer_set_surface()` | Gets `ANativeWindow` from Java Surface |
| `surface_renderer_render_frame()` | The core: YUV→RGBA conversion + surface blit |
| `surface_renderer_destroy()` | Frees buffers and releases ANativeWindow |

**Per-frame flow:**
```
AVFrame (YUV from FFmpeg)
  → sws_scale() converts to RGBA_8888 (32-byte aligned buffer)
  → ANativeWindow_lock() gets the surface buffer
  → memcpy row-by-row into the surface buffer
  → ANativeWindow_unlockAndPost() presents the frame
```

**Why ANativeWindow:** Provides direct pixel buffer access. This is the fastest path from decoded video to screen — no intermediate textures, no GPU round-trip.

---

#### `CMakeLists.txt` — Native Build Config

**Language:** CMake | **Role:** Tells Android Studio how to compile C++ and link FFmpeg

```cmake
target_link_libraries(dashcamplayer avutil swscale avcodec avformat android log)
```

Links prebuilt FFmpeg `.so` files from `jniLibs/` for each CPU architecture.

---

## 9. iOS Implementation

### File Structure

```
packages/dashcam_player/ios/
├── dashcam_player.podspec                    # CocoaPods config
├── Classes/
│   ├── DashcamPlayerPlugin.swift             # Plugin entry point
│   ├── DashcamNativePlayer.swift             # Player logic + HTTP protocol
│   ├── DashcamPlatformView.swift             # Flutter view wrapper (MTKView)
│   ├── DashcamPlatformViewFactory.swift      # View factory
│   ├── DashcamConfig.swift                   # Constants
│   ├── DashcamNativeBridge.h                 # Obj-C++ header (Swift ↔ C++)
│   ├── DashcamNativeBridge.mm               # Obj-C++ bridge implementation
│   ├── src/
│   │   ├── ffmpeg_player.h / .cpp           # FFmpeg RTSP player (C++)
│   │   └── metal_renderer.h / .mm           # Metal rendering pipeline
│   └── ffmpeg_headers/                       # FFmpeg C headers
```

### Languages Used

| Language | Where | Why |
|----------|-------|-----|
| **Ruby** | `dashcam_player.podspec` | CocoaPods (iOS dependency manager) uses Ruby |
| **Swift** | 5 `.swift` files | Flutter's recommended language for iOS plugins; modern, safe, native Apple API access |
| **Objective-C++** | `DashcamNativeBridge.mm`, `metal_renderer.mm` | Swift cannot call C++ directly. Obj-C++ bridges Swift → C++ FFmpeg |
| **C++** | `ffmpeg_player.cpp` | FFmpeg is a C library — C++ gives direct access with zero overhead |
| **C** | `ffmpeg_headers/` | FFmpeg's native API surface (libavcodec, libavformat, libswscale) |

### The Three-Language Sandwich

```
┌─────────────────────────────────────┐
│  Swift                              │  Flutter-friendly, modern
│  DashcamNativePlayer                │  HTTP calls, heartbeat, logic
│  DashcamPlatformView                │  MTKView delegate
│  DashcamPlayerPlugin                │  Channel registration
├─────────────────────────────────────┤
│  Objective-C++                      │  THE BRIDGE
│  DashcamNativeBridge.mm             │  Translates Swift ↔ C++
│  metal_renderer.mm                  │  Metal APIs + FFmpeg calls
├─────────────────────────────────────┤
│  C++                                │  Performance-critical
│  ffmpeg_player.cpp                  │  RTSP decoding pipeline
└─────────────────────────────────────┘
```

| Layer | Can call | Cannot call |
|-------|----------|-------------|
| Swift | Obj-C methods | C++ functions directly |
| Obj-C++ (.mm) | Both Obj-C AND C++ | — |
| C++ (.cpp) | C functions, FFmpeg | Obj-C or Swift |

### File-by-File Breakdown

#### `dashcam_player.podspec` — CocoaPods Config

**Language:** Ruby | **Role:** Tells CocoaPods how to build and package the plugin

Key settings:
- Platform: iOS 13.0+, Swift 5.0
- Dependency: `media_kit_libs_ios_video` (provides FFmpeg .dylib files)
- Frameworks: Metal, MetalKit, AVFoundation, CoreVideo
- C++17 with libc++
- `HAVE_FFMPEG=1` for conditional compilation

---

#### `DashcamConfig.swift` — Configuration Constants

**Language:** Swift | **Type:** `struct` (value type)

Same constants as Android:
- `dashcamIP = "192.168.169.1"`, `rtspPort = 554`, `httpPort = 80`
- Camera indices: `front = 0`, `rear = 1`, `pip = 2`
- Stream params: `1920x1080 @ 30fps`
- `userAgent = "HiCamera"`

**Why struct (not class):** Swift structs are value types — no reference counting overhead for simple data.

---

#### `DashcamPlayerPlugin.swift` — Plugin Entry Point

**Language:** Swift | **Protocol:** `FlutterPlugin`

**Key methods:**
| Method | Purpose |
|--------|---------|
| `register(with:)` | Static — Flutter calls this to register the plugin |
| `handleMethodCall(_:result:)` | Routes Dart calls: `create`, `connect`, `disconnect`, `switchCamera`, `dispose` |
| `handleCreate(viewId:)` | Looks up PlatformView, creates `DashcamNativePlayer`, links MTKView |
| `sendEvent(_:data:)` | Sends events to Dart via EventChannel |

**Registries:**
- `playerRegistry: [Int: DashcamNativePlayer]` — playerId → player
- `DashcamPlatformView.views: [Int64: DashcamPlatformView]` — viewId → PlatformView

---

#### `DashcamNativePlayer.swift` — Player Logic

**Language:** Swift | **Role:** 7-step connection sequence, heartbeat, camera switching, FFmpeg lifecycle

**Key methods:**
| Method | What it does |
|--------|-------------|
| `connect(cameraIndex:completion:)` | Dispatches to background thread, runs 7-step sequence |
| `doConnect(cameraIndex:)` | The actual 7-step connection loop with infinite retry |
| `doSwitchCamera(camera:)` | HTTP API call + RTSP reconnect with infinite retry |
| `httpGet(_:)` | Synchronous HTTP via `URLSession` + `DispatchSemaphore` |
| `startHeartbeat()` | `Timer.scheduledTimer` every 5 seconds |
| `waitForRtspPort(timeoutMs:)` | Polls TCP port 554 using raw BSD sockets |

**HTTP calls use semaphores:**
```swift
let semaphore = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: request) { ... semaphore.signal() }.resume()
semaphore.wait(timeout: .now() + .seconds(2))
```

**Why semaphores (not async/await):** The 7 steps must run sequentially on a background thread. Swift's `URLSession` is async by default, so a semaphore makes it synchronous — keeping the connection sequence simple and ordered.

**Cancellation:** `shouldStopConnecting` bool flag checked at every step and every sleep interval. Ensures `disconnect()` stops the loop within ~0.5 seconds.

---

#### `DashcamPlatformView.swift` — Flutter View Wrapper + Rendering Delegate

**Language:** Swift | **Protocols:** `FlutterPlatformView`, `MTKViewDelegate`

Three roles in one class:
1. **Flutter PlatformView** — embeds a native view in Flutter's widget tree
2. **MTKViewDelegate** — receives display-synced draw callbacks from Metal
3. **Static Registry** — lets other classes look up views by ID

**Key configuration:**
```swift
metalView.isPaused = true               // Don't auto-draw every frame
metalView.enableSetNeedsDisplay = true  // Draw only when we say so
metalView.contentMode = .scaleAspectFit // Maintain video aspect ratio
metalView.backgroundColor = .black      // Black before video starts
metalView.delegate = self               // Receive draw callbacks
```

**Static registry:** `[Int64: DashcamPlatformView]` — allows plugin to look up views by viewId.

**Draw callback:**
```swift
func draw(in view: MTKView) {
    bridge?.drawRenderer()  // Swift → Obj-C → C++ Metal renderer
}
```

---

#### `DashcamPlatformViewFactory.swift` — View Factory

**Language:** Swift | **Protocol:** `FlutterPlatformViewFactory`

```swift
func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return DashcamPlatformView(frame: frame, viewId: viewId)
}
```

**Why:** Flutter's iOS platform view API requires a factory. When Dart builds `UiKitView(viewType: 'dashcam_player_view')`, Flutter calls this factory.

---

#### `DashcamNativeBridge.h` / `.mm` — Swift to C++ Bridge

See [Section 10: Obj-C++ Bridge Deep Dive](#10-obj-c-bridge-deep-dive).

---

#### `ffmpeg_player.cpp` — FFmpeg RTSP Player

**Language:** C++ (pure — no Objective-C) | **Nearly identical to Android version**

**FFmpegPlayer struct:**
```cpp
struct FFmpegPlayer {
    MetalRenderer* renderer;          // Linked Metal renderer
    bool is_playing, is_connected;
    pthread_t playback_thread;
    pthread_mutex_t mutex;
    AVFormatContext* format_ctx;      // RTSP connection
    AVCodecContext* codec_ctx;        // Video decoder
    int video_stream_index;
};
```

Same low-latency flags as Android. Same decode loop. Only difference: `MetalRenderer*` instead of `SurfaceRenderer*`.

---

#### `metal_renderer.mm` — Metal Rendering Pipeline

See [Section 6: Native Rendering](#ios-metal--mtkview) for full details.

---

## 10. Obj-C++ Bridge Deep Dive

### Why It Exists

Swift **cannot** call C++ directly. Objective-C++ (`.mm` files) can contain both Objective-C and C++ in the same file.

```
Swift ──→ Objective-C methods (visible via .h header)
              │
              └──→ C++ functions (inside .mm implementation)
```

### `DashcamNativeBridge.h` — The Contract (8 Methods)

```objc
@interface DashcamNativeBridge : NSObject

- (NSString*)nativeTest;                                          // Test FFmpeg availability
- (NSNumber*)nativeCreateWithView:(UIView*)view;                  // Create player + renderer
- (void* _Nullable)getRendererPointer;                            // Get MetalRenderer pointer
- (void)drawRenderer;                                             // Draw frame (MTKView delegate)
- (BOOL)nativeConnect:(NSNumber*)playerPtr url:(NSString*)url;    // Open RTSP
- (void)nativeStart:(NSNumber*)playerPtr;                         // Start decode thread
- (void)nativeStop:(NSNumber*)playerPtr;                          // Stop decode thread
- (void)nativeRelease:(NSNumber*)playerPtr;                       // Free resources

@end
```

**Why `NSNumber*` for pointers:** Swift cannot handle raw C pointers easily. The C++ `FFmpegPlayer*` is cast to `long long` and wrapped as `NSNumber`.

### `DashcamNativeBridge.mm` — The Implementation

#### `nativeCreateWithView:` — Most Important Method

```objc
- (NSNumber*)nativeCreateWithView:(UIView*)view {
    FFmpegPlayer* player = ffmpeg_player_create();                          // C++ call
    MetalRenderer* renderer = metal_renderer_create((__bridge void*)view);  // C++ call + bridge cast
    ffmpeg_player_set_renderer(player, renderer);                           // Link them
    _rendererPtr = renderer;                                                // Store for delegate
    return @( (long long)player );                                          // Wrap pointer as NSNumber
}
```

**`(__bridge void*)view` explained:**
- `view` is an Objective-C `UIView*` (ARC managed)
- `(__bridge void*)` converts to raw C pointer WITHOUT transferring ownership
- C++ Metal renderer casts it back to `MTKView*`
- ARC still manages the view's lifecycle

#### Pointer Unwrapping Pattern (used by connect, start, stop, release)

```objc
- (BOOL)nativeConnect:(NSNumber*)playerPtr url:(NSString*)url {
    FFmpegPlayer* player = (FFmpegPlayer*)(long long)[playerPtr longLongValue]; // Unwrap
    const char* urlCStr = [url UTF8String];                                     // Convert string
    bool success = ffmpeg_player_connect(player, urlCStr);                      // Call C++
    return success ? YES : NO;
}
```

#### `drawRenderer` — MTKView Delegate Entry Point

```objc
- (void)drawRenderer {
    if (_rendererPtr) {
        metal_renderer_draw((MetalRenderer*)_rendererPtr);  // Obj-C → C++
    }
}
```

The MTKView delegate (Swift) holds a reference to `DashcamNativeBridge` (Obj-C), calls `drawRenderer()`, which calls `metal_renderer_draw()` (C++).

### Complete Pointer Flow

```
Swift:  bridge.nativeCreate(with: mtkView)
  │
  ▼  (Swift calls Obj-C method)
Obj-C++:  FFmpegPlayer* player = ffmpeg_player_create()         ← C++ malloc
          MetalRenderer* renderer = metal_renderer_create()     ← C++ new
          return @( (long long)player )                         ← wrap as NSNumber
  │
  ▼  (Returns to Swift)
Swift:  self.playerPtr = result   // NSNumber like @(0x12345678)

Later:
Swift:  bridge.nativeConnect(playerPtr, url: "rtsp://...")
  │
  ▼  (Swift calls Obj-C method)
Obj-C++:  FFmpegPlayer* p = (FFmpegPlayer*)(long long)[playerPtr longLongValue]  // Unwrap
          ffmpeg_player_connect(p, "rtsp://...")                                   // Call C++
```

---

## 11. PlatformView Deep Dive

### The Linking Flow (Both Platforms)

```
1. Dart builds AndroidView/UiKitView(viewType: 'dashcam_player_view')
       │
       ▼
2. Factory creates PlatformView (SurfaceView or MTKView)
       │
       ▼
3. Flutter calls onPlatformViewCreated(viewId) in Dart
   → Dart calls controller.create(viewId) via MethodChannel
       │
       ▼
4. Plugin looks up PlatformView by viewId from registry
   → Creates native player
   → Links native surface (SurfaceView or MTKView) to player
   → Returns playerId to Dart
       │
       ▼
5. Dart calls controller.connect(cameraIndex) via MethodChannel
   → Player begins streaming and rendering to the surface
```

### Android PlatformView

- **View:** `SurfaceView` with `keepScreenOn = true`
- **Registry:** `MutableMap<Int, DashcamPlatformView>`
- **Surface lifecycle:** Managed via `SurfaceHolder.Callback` with `CompletableDeferred` — Kotlin waits up to 5s for surface readiness
- **Rendering:** Direct ANativeWindow write (no delegate pattern needed)

### iOS PlatformView

- **View:** `MTKView` with `isPaused = true`, `enableSetNeedsDisplay = true`
- **Registry:** `[Int64: DashcamPlatformView]`
- **Delegate:** `MTKViewDelegate` — `draw(in:)` called on vsync when `setNeedsDisplay()` triggered
- **Rendering:** Metal GPU pipeline via command buffer submission

### iOS PlatformView Lifecycle Detail

```
init(frame, viewId)
  → Create MTKView (black, paused, Metal GPU device)
  → Set self as MTKView delegate
  → Store self in registry[viewId]

setBridge(bridge)
  → Called after nativeCreate links the bridge for draw calls

draw(in: MTKView)
  → Called by MTKView on vsync when setNeedsDisplay() triggered
  → Calls bridge.drawRenderer() → metal_renderer_draw()

unregister(viewId)
  → Remove from registry on disposal
```

---

## 12. Android vs iOS Comparison

### Architecture

| Aspect | Android | iOS |
|--------|---------|-----|
| **Language** | Kotlin | Swift |
| **C++ Bridge** | JNI (direct) | Objective-C++ (extra layer) |
| **Rendering** | ANativeWindow (CPU blit) | Metal (GPU pipeline) |
| **Surface** | SurfaceView | MTKView |
| **Pixel format** | RGBA_8888 | BGRA8Unorm (Metal byte order) |
| **HTTP client** | HttpURLConnection | URLSession + semaphore |
| **Async model** | Kotlin coroutines | GCD + Thread.sleep |
| **Heartbeat** | Coroutine Timer | Timer.scheduledTimer |
| **TCP port check** | InetSocketAddress + Socket | Raw BSD sockets (Darwin.connect) |
| **VSync** | ANativeWindow_unlockAndPost (implicit) | MTKView delegate (explicit) |
| **FFmpeg libs** | Prebuilt .so in jniLibs/ | via media_kit_libs_ios_video pod |

### Rendering Pipeline

| Aspect | Android | iOS |
|--------|---------|-----|
| Surface acquisition | ANativeWindow_fromSurface | MTKView.device + command queue |
| Color conversion | YUV → RGBA via sws_scale | YUV → BGRA via sws_scale |
| Frame upload | memcpy to ANativeWindow buffer | MTLTexture.replaceRegion |
| Presentation | ANativeWindow_unlockAndPost (implicit vsync) | Present drawable (MTKView vsync) |
| Shaders | None (direct blit) | Inline vertex + fragment (passthrough) |
| Thread model | Background decode + render | Background decode, main thread render |
| Alignment | 32-byte | 32-byte |

### Flutter Bridge

| Aspect | Android | iOS |
|--------|---------|-----|
| MethodChannel calls | IO thread via handler.post() | Main thread |
| EventChannel sends | Main thread via Handler(Looper.getMainLooper()) | Main thread via DispatchQueue |
| PlatformView registry | MutableMap<Int, View> | [Int64: View] |
| View type | AndroidView | UiKitView |
| Error codes | Structured (INVALID_ARGS, VIEW_NOT_FOUND) | FlutterError |

### Shared C++ Code

The `ffmpeg_player.cpp` file is nearly identical on both platforms:
- Same FFmpeg low-latency flags
- Same decode loop (av_read_frame → send_packet → receive_frame)
- Same pthread-based background threading
- Same mutex synchronization
- Only difference: renderer type (SurfaceRenderer vs MetalRenderer)

---

## 13. Developer Config Guide — Using With Different Dashcams

All config fields are optional. Override only what you need — everything else falls back to F9 dashcam defaults.

### Configurable Fields

| Field | Type | F9 Default | Description |
|-------|------|-----------|-------------|
| `ip` | `String?` | `192.168.169.1` | Dashcam IP address |
| `rtspPort` | `int?` | `554` | RTSP port |
| `httpPort` | `int?` | `80` | HTTP port |
| `userAgent` | `String?` | `HiCamera` | User-Agent header for HTTP requests |
| `heartbeatEndpoint` | `String?` | `http://{ip}:{port}/app/getparamvalue?param=rec` | Full heartbeat URL |
| `enterRecorderEndpoint` | `String?` | `http://{ip}:{port}/app/enterrecorder` | Full enter-recorder URL |
| `getMediaInfoEndpoint` | `String?` | `http://{ip}:{port}/app/getmediainfo` | Full get-media-info URL |
| `startLiveEndpoint` | `String?` | `http://{ip}:{port}/?custom=1&cmd=2015&par=` | Full start-live URL (camera index appended) |
| `switchCameraEndpoint` | `String?` | `http://{ip}:{port}/app/setparamvalue?param=switchcam&value=` | Full switch-camera URL (camera index appended) |
| `rtspUrl` | `String?` | `rtsp://{ip}:{rtspPort}/` | Full RTSP stream URL |

### Example 1: F9 Dashcam (Default — No Config Needed)

```dart
// Works out of the box, all F9 defaults applied
final controller = DashcamPlayerController();

DashcamPlayerWidget(
  controller: controller,
  cameraIndex: 0,
)
```

### Example 2: F9 Dashcam on a Different IP

```dart
// Only override the IP, everything else stays F9 default
final controller = DashcamPlayerController(
  config: DashcamConfig(
    ip: '192.168.1.1',
    rtspPort: 8554,
  ),
);
```

### Example 3: Partial Endpoint Override

```dart
// Same F9 dashcam but custom heartbeat endpoint
// All other endpoints use F9 defaults built from ip + httpPort
final controller = DashcamPlayerController(
  config: DashcamConfig(
    heartbeatEndpoint: 'http://192.168.169.1:80/api/keepalive',
  ),
);
```

### Example 4: Completely Different Dashcam Brand

```dart
// Full custom config for a non-F9 dashcam
final controller = DashcamPlayerController(
  config: DashcamConfig(
    // Network
    ip: '192.168.0.100',
    rtspPort: 8554,
    httpPort: 8080,
    userAgent: 'ViofoCam',

    // All HTTP API endpoints
    heartbeatEndpoint: 'http://192.168.0.100:8080/cgi-bin/heartbeat',
    enterRecorderEndpoint: 'http://192.168.0.100:8080/cgi-bin/record/start',
    getMediaInfoEndpoint: 'http://192.168.0.100:8080/cgi-bin/media',
    startLiveEndpoint: 'http://192.168.0.100:8080/cgi-bin/live?channel=',
    switchCameraEndpoint: 'http://192.168.0.100:8080/cgi-bin/switch?cam=',

    // RTSP stream URL
    rtspUrl: 'rtsp://192.168.0.100:8554/live',
  ),
);

DashcamPlayerWidget(
  controller: controller,
  cameraIndex: 0,
)
```

### Example 5: Widget Factory Shortcut

```dart
// Widget creates the controller internally with your config
DashcamPlayerWidget.withConfig(
  config: DashcamConfig(
    ip: '10.0.0.50',
    rtspPort: 554,
  ),
  cameraIndex: 0,
)
```

### Example 6: Full App Integration

```dart
import 'package:dashcam_player/dashcam_player.dart';

class MyDashcamScreen extends StatefulWidget {
  @override
  State<MyDashcamScreen> createState() => _MyDashcamScreenState();
}

class _MyDashcamScreenState extends State<MyDashcamScreen> {
  late DashcamPlayerController _controller;

  @override
  void initState() {
    super.initState();

    // Configure for your dashcam
    _controller = DashcamPlayerController(
      config: DashcamConfig(
        ip: '192.168.0.100',
        rtspPort: 8554,
        switchCameraEndpoint: 'http://192.168.0.100/cgi-bin/switch?ch=',
      ),
    );

    // Listen to events
    _controller.onStatusChanged.listen((status) {
      print('Status: $status');
    });
    _controller.onError.listen((error) {
      print('Error: $error');
    });
    _controller.onLatencyMeasured.listen((latencyMs) {
      print('Latency: ${latencyMs}ms');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DashcamPlayerWidget(
        controller: _controller,
        cameraIndex: 0,
      ),
      bottomNavigationBar: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () => _controller.switchCamera(0),
            child: Text('Front'),
          ),
          TextButton(
            onPressed: () => _controller.switchCamera(1),
            child: Text('Rear'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### How the Override Flow Works

```
Developer's App Code
  │
  ▼
DashcamConfig(
  ip: '10.0.0.1',                              ← override
  heartbeatEndpoint: 'http://10.0.0.1/api/ping' ← override
  // everything else: null                       ← will use F9 default
)
  │
  ▼  controller.create(viewId) via MethodChannel
  │  sends: { "config": { "ip": "10.0.0.1", "heartbeatEndpoint": "http://10.0.0.1/api/ping" } }
  │
  ▼  Native side (DashcamConfig.kt / .swift)
  │  ip = "10.0.0.1"                    ← from map
  │  heartbeatEndpoint = provided URL   ← from map
  │  enterRecorderEndpoint = "http://10.0.0.1:80/app/enterrecorder"  ← built from ip + F9 default path
  │  rtspUrl = "rtsp://10.0.0.1:554/"   ← built from ip + F9 default port
  │
  ▼  Player uses config.ip, config.apiHeartbeat, config.rtspUrl, etc.
```

---

## 14. Session History

### Session 1 — 15.04.2026

**Focus: Plugin exploration & architecture understanding**

- Explored the overall purpose of the custom `dashcam_player` plugin
- Documented the 3-layer architecture (Dart → Native → C++ FFmpeg)
- Deep dived into the **connection protocol** — the 7-step HTTP sequence for F9 dashcam
- Deep dived into the **FFmpeg decoding pipeline** — RTSP flags, decode loop, YUV→RGB conversion, threading model
- Deep dived into **native rendering** — Android ANativeWindow + iOS Metal rendering
- Deep dived into the **Flutter ↔ Native bridge** — MethodChannel, EventChannel, PlatformView
- Documented all **Android implementation** files (10+ files: Kotlin, C++, CMake)
- Created the initial `docs/dashcam-player-plugin-guide.md`

### Session 2 — 16.04.2026

**Focus: iOS deep dives**

- Documented all **iOS implementation** files (10+ files: Swift, Obj-C++, C++, Ruby podspec)
- Deep dived into the **Obj-C++ bridge** (`DashcamNativeBridge.h/.mm`) — why it exists, pointer wrapping, `(__bridge void*)`, the three-language sandwich
- Deep dived into the **iOS native player** (`DashcamNativePlayer.swift`) — semaphore-based HTTP, Timer heartbeat, BSD socket TCP probe, cancellation model
- Deep dived into the **iOS PlatformView** (`DashcamPlatformView.swift`) — MTKView lifecycle, MTKViewDelegate, static registry, display-synced rendering

### Session 3 — 17.04.2026

**Focus: Configurable plugin + documentation**

- Made the plugin configurable — developers can now use any dashcam, not just F9
  - Created `lib/dashcam_config.dart` — Dart config class with optional fields and F9 defaults
  - Updated `DashcamPlayerController` to accept and pass config via MethodChannel
  - Updated `DashcamPlayerWidget` with `withConfig()` factory
  - Updated Android `DashcamConfig.kt` — class with F9 defaults + map-based overrides
  - Updated Android `DashcamPlayerPlugin.kt` — extracts config from create call
  - Updated Android `DashcamNativePlayer.kt` — uses config instance instead of static constants
  - Updated iOS `DashcamConfig.swift` — class with F9 defaults + dict-based overrides
  - Updated iOS `DashcamPlayerPlugin.swift` — extracts config from create call
  - Updated iOS `DashcamNativePlayer.swift` — uses config instance instead of static constants
- Added configurable API endpoints (heartbeat, enterRecorder, getMediaInfo, startLive, switchCamera, rtspUrl)
- Generated **pipeline flow diagram** using `/ylt-flow-chart` and added as Section 1
- Added **Developer Config Guide** (Section 13) with 6 usage examples
- Added **session history** (this section)
