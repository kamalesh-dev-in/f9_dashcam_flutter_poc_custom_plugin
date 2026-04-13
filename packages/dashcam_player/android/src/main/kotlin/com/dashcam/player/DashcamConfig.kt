package com.dashcam.player

/**
 * Configuration for F9 Dashcam RTSP streaming.
 *
 * Based on learnings from native Android POC:
 * - Dashcam ignores URL paths and query parameters completely
 * - Single RTSP URL for all cameras: rtsp://192.168.169.1:554/ (plain URL)
 * - Camera switching via HTTP API: /app/setparamvalue?param=switchcam&value={0|1|2}
 * - Dashcam forces TCP transport (UDP attempts failed)
 * - Must call /app/enterrecorder before live stream
 */
object DashcamConfig {

    // Network configuration
    const val DASHCAM_IP = "192.168.169.1"
    const val RTSP_PORT = 554
    const val HTTP_PORT = 80

    // RTSP URL - Use plain URL (F9 dashcam format)
    private const val RTSP_URL_BASE = "rtsp://$DASHCAM_IP:$RTSP_PORT"
    const val RTSP_URL_PLAIN = "$RTSP_URL_BASE/"
    const val RTSP_URL = RTSP_URL_PLAIN

    // HTTP API endpoints
    const val HTTP_BASE = "http://$DASHCAM_IP:$HTTP_PORT"

    // Camera channels
    const val CAMERA_FRONT = 0
    const val CAMERA_REAR = 1
    const val CAMERA_PIP = 2

    // === Standard HTTP API endpoints ===
    const val API_ENTER_RECORDER = "$HTTP_BASE/app/enterrecorder"
    const val API_EXIT_RECORDER = "$HTTP_BASE/app/exitrecorder"
    const val API_SWITCH_CAMERA = "$HTTP_BASE/app/setparamvalue?param=switchcam&value="
    const val API_HEARTBEAT = "$HTTP_BASE/app/getparamvalue?param=rec"
    const val API_GET_MEDIA_INFO = "$HTTP_BASE/app/getmediainfo"

    // === Vidure's HTTP API endpoints ===
    // Step 1: Enter recorder mode
    const val API_ENTER_RECORDER_VIDURE = "$HTTP_BASE/?custom=1&cmd=3023#3035"

    // Step 2: Get stream URL
    const val API_GET_STREAM_URL = "$HTTP_BASE/?custom=1&cmd=2019"

    // Step 3: Start live preview - CRITICAL! This activates the stream
    const val API_START_LIVE = "$HTTP_BASE/?custom=1&cmd=2015&par="

    // User-Agent header required by dashcam
    const val USER_AGENT = "HiCamera"
}
