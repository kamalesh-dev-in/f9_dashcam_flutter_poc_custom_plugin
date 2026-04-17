package com.dashcam.player

/**
 * Configuration for dashcam RTSP streaming.
 *
 * Supports developer overrides with F9 dashcam defaults as fallback.
 * All endpoints can be overridden individually — if not provided,
 * they're built from F9 default paths + the effective base URL.
 */
class DashcamConfig(map: Map<String, Any>? = null) {

    companion object {
        // F9 Dashcam defaults
        const val DEFAULT_IP = "192.168.169.1"
        const val DEFAULT_RTSP_PORT = 554
        const val DEFAULT_HTTP_PORT = 80
        const val DEFAULT_USER_AGENT = "HiCamera"

        // F9 default endpoint paths
        const val DEFAULT_HEARTBEAT_PATH = "/app/getparamvalue?param=rec"
        const val DEFAULT_ENTER_RECORDER_PATH = "/app/enterrecorder"
        const val DEFAULT_GET_MEDIA_INFO_PATH = "/app/getmediainfo"
        const val DEFAULT_START_LIVE_PATH = "/?custom=1&cmd=2015&par="
        const val DEFAULT_SWITCH_CAMERA_PATH = "/app/setparamvalue?param=switchcam&value="

        const val CAMERA_FRONT = 0
        const val CAMERA_REAR = 1
        const val CAMERA_PIP = 2
    }

    // Effective values (override or F9 default)
    val ip: String = (map?.get("ip") as? String) ?: DEFAULT_IP
    val rtspPort: Int = (map?.get("rtspPort") as? Number)?.toInt() ?: DEFAULT_RTSP_PORT
    val httpPort: Int = (map?.get("httpPort") as? Number)?.toInt() ?: DEFAULT_HTTP_PORT
    val userAgent: String = (map?.get("userAgent") as? String) ?: DEFAULT_USER_AGENT

    // Base URLs
    private val httpBase: String = "http://$ip:$httpPort"

    // RTSP URL (full override or built from ip + port)
    val rtspUrl: String = (map?.get("rtspUrl") as? String) ?: "rtsp://$ip:$rtspPort/"

    // HTTP API endpoints (full override or built from base + F9 default path)
    val apiHeartbeat: String =
        (map?.get("heartbeatEndpoint") as? String) ?: "$httpBase$DEFAULT_HEARTBEAT_PATH"
    val apiEnterRecorder: String =
        (map?.get("enterRecorderEndpoint") as? String) ?: "$httpBase$DEFAULT_ENTER_RECORDER_PATH"
    val apiGetMediaInfo: String =
        (map?.get("getMediaInfoEndpoint") as? String) ?: "$httpBase$DEFAULT_GET_MEDIA_INFO_PATH"
    val apiStartLive: String =
        (map?.get("startLiveEndpoint") as? String) ?: "$httpBase$DEFAULT_START_LIVE_PATH"
    val apiSwitchCamera: String =
        (map?.get("switchCameraEndpoint") as? String) ?: "$httpBase$DEFAULT_SWITCH_CAMERA_PATH"
}
