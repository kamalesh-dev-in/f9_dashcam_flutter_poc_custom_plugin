# EEASY-TECH – APP Phone Connection API Documentation

## Table of Contents
- [Media Info](#media-info)
- [Real-Time RTSP Streaming](#real-time-rtsp-streaming)
  - [Overview](#overview)
  - [Prerequisites](#prerequisites)
  - [Connection Flow](#connection-flow)
  - [Encoding Format](#encoding-format)
- [Parameters](#parameters)
  - [Get Recording Status](#get-recording-status)
  - [Get Video Encoding Format](#get-video-encoding-format)
  - [Switch Camera Lens](#switch-camera-lens)
- [GPS Status Messages](#gps-status-messages)
  - [Overview](#gps-overview)
  - [Return Parameters](#gps-return-parameters)
  - [GPS Data Format](#gps-data-format)

---

## Media Info

**Endpoint:** `GET http://192.168.169.1/app/getmediainfo`

Returns RTSP connection details for the device.

**Example Response:**
```json
{
  "result": 0,
  "info": {
    "rtsp": "rtsp://192.168.169.1",
    "transport": "tcp",
    "port": 5000
  }
}
```

| Field | Description |
|-------|-------------|
| `rtsp` | Base RTSP server address |
| `transport` | Transfer protocol (`tcp` or `udp`) |
| `port` | Port used for communication |

---

## Real-Time RTSP Streaming

### Overview

| Field | Details |
|-------|---------|
| **RTSP Interface** | `rtsp://192.168.169.1:554` or `rtsp://192.168.169.1:8554` |
| **Transfer Layer** | UDP or TCP *(TCP is recommended)* |
| **RTSP Version** | RTSP/1.0 |
| **Supported Methods** | `OPTIONS`, `DESCRIBE`, `SETUP`, `PLAY`, `TEARDOWN` |
| **Video Encoding** | H.264 / H.265 |
| **Audio Encoding** | AAC |

> **Performance Targets:** End-to-end latency should be under 500 ms (ideally ~200 ms). Bitrate should remain below 2 Mbps to ensure fluency and low latency.

---

### Prerequisites

Before opening the RTSP stream, complete the following steps:

1. **(Optional)** Send the enter-recorder request:
   ```
   GET http://192.168.169.1/app/enterrecorder
   ```

2. **(Optional)** Send a heartbeat regularly (e.g., every 5 seconds):
   ```
   GET http://192.168.169.1/app/getparamvalue?param=rec
   ```

3. **(Optional)** Fetch media info to confirm stream parameters:
   ```
   GET http://192.168.169.1/app/getmediainfo
   ```

---

### Connection Flow

The RTSP session follows the standard RTSP/1.0 handshake sequence:

| Step | Direction | Method | Description |
|------|-----------|--------|-------------|
| 1 | Client → Server | `OPTIONS` | Client requests list of supported methods |
| 2 | Server → Client | `OPTIONS` response | Server returns supported methods |
| 3 | Client → Server | `DESCRIBE` | Client requests session description (SDP) |
| 4 | Server → Client | `DESCRIBE` response | Server returns SDP including SPS/PPS, media name, codec info |
| 5 | Client → Server | `SETUP` | Client requests session setup with transport protocol and port |
| 6 | Server → Client | `SETUP` response | Server returns its port and session identifier |
| 7 | Client → Server | `PLAY` | Client begins playback |
| 8 | Server → Client | `PLAY` response + stream | Server sends session ID, RTP sequence/timestamp, and begins streaming |
| 9 | Client → Server | `TEARDOWN` | Client closes the connection |
| 10 | Server → Client | `TEARDOWN` response | Server stops transmission and closes connection |

---

### Encoding Format

The encoding format in use can be queried via the `encodec` parameter. See [Get Video Encoding Format](#get-video-encoding-format).

---

## Parameters

### Get Recording Status

**Endpoint:** `GET http://192.168.169.1/app/getparamvalue?param=rec`

Returns the current recording state of the device.

**Example Response:**
```json
{
  "result": 0,
  "info": {
    "value": 1
  }
}
```

| `value` | Meaning |
|---------|---------|
| `1` | Recording is **ON** |
| `0` | Recording is **OFF** |

---

### Get Video Encoding Format

**Endpoint:** `GET http://192.168.169.1/app/getparamvalue?param=encodec`

Returns the current video encoding format used by the device.

**Example Response:**
```json
{
  "result": 0,
  "info": {
    "value": 1
  }
}
```

| `value` | Encoding Format |
|---------|----------------|
| `0` | H.264 |
| `1` | H.265 |

---

### Switch Camera Lens

**Endpoint:** `GET http://192.168.169.1/app/setparamvalue`

Switches the active camera lens on the device. Use this when the stream switch needs to be handled by the APP rather than the device itself.

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `param` | String | Must be `switchcam` |
| `value` | Integer | Lens index (see table below) |

**Example Request:**
```
GET http://192.168.169.1/app/setparamvalue?param=switchcam&value=0
```

| `value` | Camera |
|---------|--------|
| `0` | Front |
| `1` | Rear |
| `2` | Picture-in-Picture |

**Example Response:**
```json
{
  "result": 0,
  "info": "set success"
}
```

---

## GPS Status Messages

### GPS Overview

The device pushes real-time GPS and motion data (speed, coordinates, G-sensor, altitude, etc.) to the APP automatically — no request from the APP is required.

**Return Interface (Device → APP):**

| Field | Value |
|-------|-------|
| **IP** | `192.168.169.1` |
| **Port** | `5000` |

---

### GPS Return Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `msgid` | String | Message ID indicating the event type |
| `info` | JSON Object | Message content corresponding to `msgid` |
| `value` | String | Current GPS data in the defined parameter format |
| `time` | Long | Unix timestamp (seconds) of message transmission |

---

### GPS Data Format

Each GPS message contains the following fields:

| Field | Example | Notes |
|-------|---------|-------|
| Date | `2023/07/06` | Format: `yyyy/MM/dd` |
| Time | `16:25:59` | Format: `HH:mm:ss` |
| Latitude | `N:22.524790` | `N` = North, `S` = South (degrees) |
| Longitude | `E:113.935379` | `E` = East, `W` = West (degrees) |
| Speed | `80.00` | Unit: `km/h` (must be converted if sourced in other units) |
| Heading | `271.80` | Unit: degrees, range: `0–360` |
| Altitude | `500.00` | Unit: metres, range: `-9999–9999` |
| Satellites | `17` | Number of satellites locked (indicates GPS signal strength) |
| G-sensor X | `-0.004` | Unit: G |
| G-sensor Y | `-0.137` | Unit: G |
| G-sensor Z | `+0.054` | Unit: G |
