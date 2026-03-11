# APP Phone Connection — API Reference

> **Base URL:** `http://192.168.169.1`  
> **Protocol:** HTTP (GET), TCP Push (port 5000), RTSP (port 554 / 8554)  
> **Response Format:** JSON — `{ "result": 0, "info": { ... } }` — `result: 0` = success, any other value = error.

---

## Table of Contents

1. [Basic Information](#1-basic-information)
2. [Device Management](#2-device-management)
3. [Device File Management](#3-device-file-management)
4. [Normal Setting Items](#4-normal-setting-items)
5. [Push Messages (TCP)](#5-push-messages-tcp)
6. [Real-Time Stream (RTSP)](#6-real-time-stream-rtsp)

---

## 1. Basic Information

### 1.1 Get Product Information

**GET** `/app/getproductinfo`

> Returns product model, manufacturer, chip platform, and solution provider.

**Request Parameters:** None

**Response Parameters:**

| Parameter | Type   | Description                      |
|-----------|--------|----------------------------------|
| model     | string | Product model (e.g. "recorder")  |
| company   | string | Manufacturer name                |
| soc       | string | Chip platform                    |
| sp        | string | Solution provider (optional)     |

---

### 1.2 Get Device Information

**GET** `/app/getdeviceattr`

> Returns basic device identifiers, firmware version, Wi-Fi info, and camera count.

**Request Parameters:** None

**Response Parameters:**

| Parameter  | Type   | Description                                                       |
|------------|--------|-------------------------------------------------------------------|
| uuid       | string | Unique device identifier (MAC address or SN)                     |
| softver    | string | Current firmware version                                          |
| otaver     | string | OTA upgrade version number                                        |
| hwver      | string | Hardware version                                                  |
| ssid       | string | Wi-Fi SSID                                                        |
| bssid      | string | Wi-Fi MAC address                                                 |
| camnum     | int    | Number of cameras                                                 |
| curcamid   | int    | Current camera ID (0 = front, 1 = rear)                          |
| wifireboot | int    | Whether Wi-Fi restart is required after changing Wi-Fi settings  |

---

### 1.3 Get Storage Information

**GET** `/app/getsdinfo`

> Returns the SD/TF card status and capacity.

**Request Parameters:** None

**Response Parameters:**

| Parameter | Type | Description                                                                    |
|-----------|------|--------------------------------------------------------------------------------|
| status    | int  | 0=Normal, 1=Unformatted, 2=Removed, 3=Damaged, 10=Locked, 11=Low speed, 12=Abnormal, 13=Formatting, 99=Unknown |
| free      | int  | Remaining capacity (MB)                                                        |
| total     | int  | Total capacity (MB)                                                            |

---

### 1.4 Get Battery Status

**GET** `/app/getbatteryinfo`

> Returns the current battery percentage and charging state.

**Request Parameters:** None

**Response Parameters:**

| Parameter | Type | Description                              |
|-----------|------|------------------------------------------|
| capacity  | int  | Battery level 0–100 (%)                 |
| charge    | int  | 0 = Not charging, 1 = Charging          |

---

### 1.5 Get Media Information

**GET** `/app/getmediainfo`

> Returns the RTSP server address, transmission protocol, and TCP push port.

**Request Parameters:** None

**Response Parameters:**

| Parameter | Type   | Description                                      |
|-----------|--------|--------------------------------------------------|
| rtsp      | string | RTSP server address (e.g. "rtsp://192.168.169.1")|
| transport | string | RTSP transport protocol: "tcp" or "udp"          |
| port      | int    | TCP socket port for push messages (e.g. 5000)   |

---

### 1.6 Get Recording Duration

**GET** `/app/getrecduration`

> Returns the current recording file duration (not total continuous time).

**Request Parameters:** None

**Response Parameters:**

| Parameter | Type | Description                            |
|-----------|------|----------------------------------------|
| duration  | int  | Duration of the current recording file (seconds) |

---

### 1.7 Get Device Capacity (Feature Flags)

**GET** `/app/capability`

> Returns a bit-string indicating which optional features the device supports (GPS, file locking, photo, Wi-Fi editing, streaming mode, etc.).

**Request Parameters:** None

**Response Parameters:**

| Parameter | Type   | Description                                                                     |
|-----------|--------|---------------------------------------------------------------------------------|
| value     | string | Bit string (left to right): each bit represents a feature flag (see docs for bit definitions) |

**Key bit definitions (left to right):**
- Bit 0: GPS data service support level (0–4)
- Bit 1: Device type (0=recorder, 1=motion camera)
- Bit 2: Parking monitoring photo album support
- Bit 3: File locking via APP
- Bit 4: Deleting locked files
- Bit 5: Photo snapshot mode
- Bit 6: Video playback mode (0=HTTP, 1=RTSP/TCP, 2=RTSP/UDP)
- Bit 7: Photo function support
- Bit 8: Wi-Fi name/password modification permissions

---

## 2. Device Management

### 2.1 Set Time Zone

**GET** `/app/settimezone?timezone={value}`

> Syncs the mobile phone's time zone to the device.

**Request Parameters:**

| Parameter | Type | Description                                          |
|-----------|------|------------------------------------------------------|
| timezone  | int  | UTC offset, e.g. `8` = GMT+8:00, `-5` = GMT-5:00   |

**Response Parameters:** None (`"info": "set success"`)

---

### 2.2 Set Date and Time

**GET** `/app/setsystime?date={yyyyMMddHHmmss}`

> Syncs the mobile phone's current date and time to the device.

**Request Parameters:**

| Parameter | Type | Description                                       |
|-----------|------|---------------------------------------------------|
| date      | long | Date/time in format `yyyyMMddHHmmss` (e.g. `20210123153650`) |

**Response Parameters:** None (`"info": "set success"`)

---

### 2.3 Modify Wi-Fi Name

**GET** `/app/setwifi?wifissid={name}`

> Changes the device's Wi-Fi SSID.

**Request Parameters:**

| Parameter | Type   | Description                         |
|-----------|--------|-------------------------------------|
| wifissid  | string | New Wi-Fi name (e.g. "AP-11223344") |

**Response Parameters:** None (`"info": "set success"`)

---

### 2.4 Modify Wi-Fi Password

**GET** `/app/setwifi?wifipwd={password}`

> Changes the device's Wi-Fi password.

**Request Parameters:**

| Parameter | Type   | Description                    |
|-----------|--------|--------------------------------|
| wifipwd   | string | New Wi-Fi password (e.g. "12345678") |

**Response Parameters:** None (`"info": "set success"`)

---

### 2.5 Restart Wi-Fi

**GET** `/app/wifireboot`

> Restarts the Wi-Fi process after changing SSID or password.

**Request Parameters:** None  
**Response Parameters:** None (`"info": "reboot success"`)

---

### 2.6 Format SD/TF Card

**GET** `/app/sdformat`

> Formats the SD/TF card, erasing all content.

**Request Parameters:** None  
**Response Parameters:** None (`"info": "set success"`)

---

### 2.7 Restore Factory Settings

**GET** `/app/reset`

> Resets all device settings to factory defaults.

**Request Parameters:** None  
**Response Parameters:** None (`"info": "set success"`)

---

### 2.8 Switch Camera

**GET** `/app/setparamvalue?param=switchcam&value={index}`

> Switches the active camera for multi-camera devices.

**Request Parameters:**

| Parameter | Type   | Description                                          |
|-----------|--------|------------------------------------------------------|
| param     | string | Fixed value: `switchcam`                             |
| value     | int    | 0 = Front, 1 = Rear, 2 = Picture-in-Picture          |

**Response Parameters:** None (`"info": "set success"`)

---

### 2.9 Take Photo (Snapshot)

**GET** `/app/snapshot`

> Triggers the device to capture a photo.

**Request Parameters:** None  
**Response Parameters:** None (`"info": "snapshot success"`)

---

### 2.10 Lock Current Recording File

**GET** `/app/lockvideo`

> Changes the current normal recording to an emergency lock file (protected from overwrite).

**Request Parameters:** None  
**Response Parameters:** None (`"info": "lock success"`)

---

### 2.11 Enter Recorder

**GET** `/app/enterrecorder`

> Notifies the device that the APP has successfully connected and entered the recorder view.

**Request Parameters:** None  
**Response Parameters:** None (`"info": "set success"`)

---

### 2.12 Exit Recorder

**GET** `/app/exitrecorder`

> Notifies the device that the APP has exited the recorder view.

**Request Parameters:** None  
**Response Parameters:** None (`"info": "set success"`)

---

### 2.13 Enter / Exit Menu Mode

**GET** `/app/setting?param={enter|exit}`

> Notifies the device when the APP enters or exits the settings menu.

**Request Parameters:**

| Parameter | Type   | Description                                    |
|-----------|--------|------------------------------------------------|
| param     | string | `enter` = Enter menu mode, `exit` = Exit menu mode |

**Response Parameters:** None (`"info": "set success"`)

---

### 2.14 Enter / Exit Playback Mode

**GET** `/app/playback?param={enter|exit}`

> Notifies the device when the APP enters or exits playback mode. Required before opening RTSP small-streaming playback.

**Request Parameters:**

| Parameter | Type   | Description                                       |
|-----------|--------|---------------------------------------------------|
| param     | string | `enter` = Enter playback mode, `exit` = Exit playback mode |

**Response Parameters:** None (`"info": "set success"`)

---

## 3. Device File Management

### 3.1 Get File List (One-time)

**GET** `/app/getfilelist`

> Returns all files on the device grouped by folder type in a single response.

**Request Parameters:** None

**Response Parameters (array of folders):**

| Parameter      | Type      | Description                                              |
|----------------|-----------|----------------------------------------------------------|
| folder         | string    | Folder type: `loop`, `emr`, `event`, `park`             |
| count          | int       | Number of files in folder                                |
| files          | JsonArray | Array of file objects                                    |
| files[].name   | string    | Relative file path                                       |
| files[].duration | int    | File duration in seconds (0 for pictures)                |
| files[].size   | int       | File size in KB                                          |
| files[].createtime | int  | Unix timestamp of file creation (seconds)                |
| files[].createtimestr | string | Creation date `yyyyMMddHHmmss`                  |
| files[].type   | int       | 1 = Picture, 2 = Video                                  |

---

### 3.2 Get File List (Paging)

**GET** `/app/getfilelist?folder={type}&start={n}&end={n}`

> Returns a paginated subset of files from a specific folder.

**Request Parameters:**

| Parameter | Type   | Description                                                |
|-----------|--------|------------------------------------------------------------|
| folder    | string | `loop`, `emr`, `event`, or `park`                         |
| start     | int    | Start index (0-based)                                      |
| end       | int    | End index (inclusive, 0-based)                             |

**Response Parameters:** Same structure as one-time file list above.

---

### 3.3 Get File Thumbnail

**GET** `/app/getthumbnail?file={relative_path}`

> Returns the thumbnail image data for a given video or picture file.

**Request Parameters:**

| Parameter | Type   | Description                        |
|-----------|--------|------------------------------------|
| file      | string | Relative path to the file          |

**Response:** Raw image bytes (the thumbnail file content)

---

### 3.4 Video Playback — Source File (HTTP)

**GET** `http://192.168.169.1:80/{file_path}`

> Streams the original video file over HTTP for playback (supports HTTP Range requests).

**Supported formats:** `.ts`, `.mp4`, `.mov`  
**Request Parameters:** None (file path is in the URL)  
**Response:** Raw video file bytes

---

### 3.5 Video Playback — Small Streaming (RTSP)

**RTSP** `rtsp://192.168.169.1:554/{file_path}` or `:8554/{file_path}`

> Streams a lower-bandwidth version of the video over RTSP. Requires entering playback mode first (`/app/playback?param=enter`).

**Supported RTSP methods:** OPTIONS, DESCRIBE, SETUP, TEARDOWN, PLAY, PAUSE  
**Media encoding:** Video H.264/H.265, Audio AAC

---

### 3.6 Download File (Video or Picture)

**GET** `/{relative_file_path}`

> Downloads a historical video or picture file directly from the device.

**Example:** `http://192.168.169.1/mnt/sdcard/VIDEO_F/20201120190300_f.ts`

**Request Parameters:** None  
**Response:** Raw file bytes

---

### 3.7 Download GPS Data File (from GPS folder)

**GET** `/GPSdata/{filename}.TXT`

> Downloads a GPS data text file from the dedicated GPS data folder.

**Request Parameters:** None

**Response:** Plain-text GPS data file, one record per second:

```
2023/07/06 16:25:59 N:22.524790 E:113.935379 80.00 km/h 271.80 500.00 17 x:-0.004 y:-0.137 z:+0.054
```

| Field              | Description                                |
|--------------------|--------------------------------------------|
| Date               | `yyyy/MM/dd`                               |
| Time               | `HH:mm:ss`                                 |
| Latitude           | N/S + degrees (6 decimal places)           |
| Longitude          | E/W + degrees (6 decimal places)           |
| Speed              | km/h (1 decimal place)                     |
| Heading            | Degrees 0–360                              |
| Altitude           | Meters, range -9999 to 9999               |
| Satellites         | Count                                      |
| G-sensor X/Y/Z     | Acceleration in G (2 decimal places)       |

---

### 3.8 Download GPS Data (Relative Path)

**GET** `/{GPSPATH_from_filelist}`

> Downloads the GPS file using the relative path returned in the `GPSPATH` field of the file list response.

**Request Parameters:** None  
**Response:** Same GPS text format as above.

---

### 3.9 Delete File

**GET** `/app/deletefile?file={relative_path}`

> Deletes a specific file from the device.

**Request Parameters:**

| Parameter | Type   | Description                    |
|-----------|--------|--------------------------------|
| file      | string | Relative path to the file      |

**Response Parameters:** None (`"info": "delete success"`)

---

### 3.10 Upload File (OTA / Firmware)

**POST** `/upload`

> Uploads a firmware binary (bin/pkg) file to the device for OTA updates.

**Request Parameters:** File path on device + actual byte size (in the POST body)  
**Response:** HTTP 200 OK on success; JSON error with `result: 2` (SD removed) or `result: 3` (not formatted) on failure.

---

## 4. Normal Setting Items

All settings share two base endpoints:

| Endpoint            | Purpose                        |
|---------------------|--------------------------------|
| `/app/getparamitems` | Get allowed parameter list    |
| `/app/getparamvalue` | Get current value of a setting |
| `/app/setparamvalue` | Set a new value for a setting  |

### 4.1 Query All Parameter Lists

**GET** `/app/getparamitems?param=all`

> Returns the full list of all device settings with their valid options and index values.

**Response Parameters:**

| Parameter | Type             | Description                                 |
|-----------|------------------|---------------------------------------------|
| name      | string           | Setting item name                           |
| items     | JsonArray(String)| Human-readable list of options              |
| index     | JsonArray(int)   | Integer value corresponding to each option  |

---

### 4.2 Summary of All Setting Items

The following settings all use `/app/getparamitems?param={name}` to get options and `/app/getparamvalue?param={name}` to get the current value. Use `/app/setparamvalue?param={name}&value={index}` to change the value.

| Setting Name          | param key              | Options (index: label)                                                     |
|-----------------------|------------------------|----------------------------------------------------------------------------|
| Microphone Switch     | `mic`                  | 0=off, 1=on                                                                |
| Time Watermark        | `osd`                  | 0=off, 1=on                                                                |
| Logo Watermark        | `logo_osd`             | 0=off, 1=on                                                                |
| Recording Resolution  | `rec_resolution`       | 0=720P, 1=1080P, 2=1296P, 3=2K                                             |
| Recording Duration    | `rec_split_duration`   | 0=1MIN, 1=2MIN                                                             |
| Video Encoding Format | `encodec`              | 0=h.264, 1=h.265                                                           |
| Speaker Volume        | `speaker`              | 0=off, 1=low, 2=middle, 3=high, 4=very high                               |
| Collision Sensitivity | `gsr_sensitivity`      | 0=high, 1=low, 2=off                                                       |
| Recording Status      | `rec`                  | 0=off (stop), 1=on (start)                                                 |
| Language Type         | `language`             | 0=en_US, 1=zh_CN, 2=zh_CHT, 3=ja, 4=ru, 5=th, 6=cran                    |
| Timelapse Frame Rate  | `timelapse_rate`       | 0=off, 1=1fps, 2=2fps, 3=5fps                                              |
| Parking Rec. Duration | `park_record_time`     | 0=off, 1=12hour, 2=24hour, 3=48hour                                        |
| Parking Collision Sens.| `park_gsr_sensitivity` | 0=high, 1=low, 2=off                                                      |
| Parking Monitor Mode  | `parking_mode`         | 0=off, 1=timelapse, 2=normrec                                              |
| Parking Monitor Switch| `parking_monitor`      | 0=off, 1=on                                                                |
| Light Frequency       | `light_fre`            | 0=50Hz, 1=60Hz                                                             |
| Rear Mirror Switch    | `rear_mirror`          | 0=off, 1=on                                                                |
| Wide Dynamic Switch   | `wdr`                  | 0=off, 1=on                                                                |
| Voice Control Switch  | `voice_control`        | 0=off, 1=on                                                                |
| Screen Standby        | `screen_standby`       | 0=off, 1=10s, 2=30s, 3=60s                                                |
| Auto Power-off        | `auto_poweroff`        | 0=off, 1=1H, 2=12H                                                         |
| ADAS Switch           | `adas`                 | 0=off, 1=on                                                                |
| Boot Sound Switch     | `boot_sound`           | 0=off, 1=on                                                                |
| Video Vertical Flip   | `video_filp`           | 0=off, 1=on                                                                |
| Video Horizontal Mirror| `video_mirror`        | 0=off, 1=on                                                                |
| Key Tone Switch       | `key_tone`             | 0=off, 1=on                                                                |

> **Note:** All setting parameter names are case-sensitive and must be **lowercase**.

---

### 4.3 Get All Current Values

**GET** `/app/getparamvalue?param=all`

> Returns the current value for every setting item on the device.

**Response:** Array of `{ "name": "...", "value": N }` objects for each setting.

---

## 5. Push Messages (TCP)

All push messages are sent **from the device to the APP** via a persistent TCP socket connection.

**Device TCP server:** `192.168.169.1:5000`

All messages share this base structure:

```json
{
  "msgid": "<event_type>",
  "info": { ... },
  "time": 1593422089
}
```

| Field  | Type   | Description                              |
|--------|--------|------------------------------------------|
| msgid  | string | Event type identifier                    |
| info   | object | Event-specific payload                   |
| time   | long   | Unix timestamp of the event (seconds)    |

---

### 5.1 Recording Status Change

**msgid:** `rec`

> Notified when recording starts or stops via a hardware button (not via APP).

| Field        | Type | Description              |
|--------------|------|--------------------------|
| info.value   | int  | 0=start, 1=stop          |

---

### 5.2 Microphone Status Change

**msgid:** `mic`

> Notified when microphone is toggled via hardware.

| Field        | Type | Description              |
|--------------|------|--------------------------|
| info.value   | int  | 0=off, 1=on              |

---

### 5.3 Battery Status Change

**msgid:** `battery`

> Notified when battery level or charging state changes.

| Field           | Type | Description                            |
|-----------------|------|----------------------------------------|
| info.capacity   | int  | Battery percentage 0–100               |
| info.charge     | int  | 0=not charging, 1=charging             |

---

### 5.4 Storage Card Status Change

**msgid:** `sd`

> Notified when SD/TF card is inserted, removed, or its state changes.

| Field        | Type | Description                                         |
|--------------|------|-----------------------------------------------------|
| info.status  | int  | 0=normal, 1=unformatted, 2=removed, 99=unknown      |

---

### 5.5 File Deletion Status Change

**msgid:** `file_del`

> Notified when a file is deleted on the device (non-APP deletion).

| Field        | Type   | Description                            |
|--------------|--------|----------------------------------------|
| info.name    | string | Path of the deleted file               |
| info.type    | int    | 1=picture, 2=video                     |

---

### 5.6 File Addition Status Change (Optional)

**msgid:** `file_add`

> Notified when a new file is added to the device.

| Field        | Type   | Description                            |
|--------------|--------|----------------------------------------|
| info.name    | string | Path of the new file                   |
| info.type    | int    | 1=picture, 2=video                     |

---

### 5.7 File Locking Status Change

**msgid:** `rec_lock`

> Notified when a recording file is locked via hardware (not via APP).

| Field        | Type | Description                       |
|--------------|------|-----------------------------------|
| info.value   | int  | 0=stop locking, 1=start locking   |

---

### 5.8 Real-Time GPS Information

**msgid:** `gps`

> Periodically reports the device's live GPS motion state (speed, location, G-sensor, etc.).

| Field        | Type   | Description                                            |
|--------------|--------|--------------------------------------------------------|
| info.value   | string | GPS data string (see format below)                     |

**GPS data format:**
```
yyyy/MM/dd HH:mm:ss N:{lat} E:{lon} {speed} km/h {heading} {altitude} {satellites} x:{Gx} y:{Gy} z:{Gz}
```

---

### 5.9 GPS Satellite Status Change

**msgid:** `gps_satellite`

> Periodically reports the number of visible GPS satellites and their signal values.

| Field        | Type   | Description                                              |
|--------------|--------|----------------------------------------------------------|
| info.value   | string | Comma-separated list of satellite signal values          |

**Example:** `"10,12,5,3,6,8,6,0,0,0"`

---

### 5.10 Camera Plug/Unplug Status Change

**msgid:** `cam_plugin`

> Notified when a camera is physically plugged or unplugged.

| Field           | Type | Description                                        |
|-----------------|------|----------------------------------------------------|
| info.action     | int  | 0=unplugged, 1=plugged in                          |
| info.curcamid   | int  | ID of the currently active camera (after change)   |
| info.camnum     | int  | Total number of cameras (after change)             |

---

## 6. Real-Time Stream (RTSP)

**RTSP URL:** `rtsp://192.168.169.1:554` or `rtsp://192.168.169.1:8554`

> Provides live camera preview streaming to the APP.

| Property               | Value                                                        |
|------------------------|--------------------------------------------------------------|
| Transport Layer        | UDP or TCP (TCP preferred)                                   |
| RTSP Version           | RTSP/1.0                                                     |
| Supported Methods      | OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN                    |
| Media Encoding         | Video: H.264 / H.265 · Audio: AAC                           |
| Bitrate Recommendation | < 2 Mbps                                                    |
| Delay Requirement      | < 500 ms (target ~200 ms end-to-end)                        |

**Prerequisites before opening RTSP:**
1. Send `GET /app/enterrecorder` (optional but recommended)
2. Send periodic heartbeat every ~5 seconds: `GET /app/getparamvalue?param=rec`
3. Send `GET /app/getmediainfo` to retrieve transport settings

**RTSP Connection Flow:**
1. OPTIONS → get supported methods
2. DESCRIBE → get SDP (media name, codec, resolution)
3. SETUP → establish session, negotiate ports
4. PLAY → start audio/video stream
5. TEARDOWN → close connection
