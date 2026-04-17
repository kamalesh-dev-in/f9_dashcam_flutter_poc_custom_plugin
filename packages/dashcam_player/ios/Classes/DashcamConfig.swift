import Foundation

/// Configuration for dashcam RTSP streaming.
///
/// Supports developer overrides with F9 dashcam defaults as fallback.
/// All endpoints can be overridden individually — if not provided,
/// they're built from F9 default paths + the effective base URL.
class DashcamConfig {

    // F9 Dashcam defaults
    static let DEFAULT_IP = "192.168.169.1"
    static let DEFAULT_RTSP_PORT = 554
    static let DEFAULT_HTTP_PORT = 80
    static let DEFAULT_USER_AGENT = "HiCamera"

    // F9 default endpoint paths
    static let DEFAULT_HEARTBEAT_PATH = "/app/getparamvalue?param=rec"
    static let DEFAULT_ENTER_RECORDER_PATH = "/app/enterrecorder"
    static let DEFAULT_GET_MEDIA_INFO_PATH = "/app/getmediainfo"
    static let DEFAULT_START_LIVE_PATH = "/?custom=1&cmd=2015&par="
    static let DEFAULT_SWITCH_CAMERA_PATH = "/app/setparamvalue?param=switchcam&value="

    static let CAMERA_FRONT = 0
    static let CAMERA_REAR = 1
    static let CAMERA_PIP = 2

    // Camera names for UI
    static let cameraNames = ["Front", "Rear", "PiP"]

    // Effective network values
    let ip: String
    let rtspPort: Int
    let httpPort: Int
    let userAgent: String

    // Full endpoint URLs (override or built from base + F9 default path)
    let rtspUrl: String
    let apiHeartbeat: String
    let apiEnterRecorder: String
    let apiGetMediaInfo: String
    let apiStartLive: String
    let apiSwitchCamera: String

    /// Create with F9 defaults (no overrides)
    init() {
        self.ip = DashcamConfig.DEFAULT_IP
        self.rtspPort = DashcamConfig.DEFAULT_RTSP_PORT
        self.httpPort = DashcamConfig.DEFAULT_HTTP_PORT
        self.userAgent = DashcamConfig.DEFAULT_USER_AGENT

        let httpBase = "http://\(ip):\(httpPort)"
        self.rtspUrl = "rtsp://\(ip):\(rtspPort)/"
        self.apiHeartbeat = "\(httpBase)\(DashcamConfig.DEFAULT_HEARTBEAT_PATH)"
        self.apiEnterRecorder = "\(httpBase)\(DashcamConfig.DEFAULT_ENTER_RECORDER_PATH)"
        self.apiGetMediaInfo = "\(httpBase)\(DashcamConfig.DEFAULT_GET_MEDIA_INFO_PATH)"
        self.apiStartLive = "\(httpBase)\(DashcamConfig.DEFAULT_START_LIVE_PATH)"
        self.apiSwitchCamera = "\(httpBase)\(DashcamConfig.DEFAULT_SWITCH_CAMERA_PATH)"
    }

    /// Create with overrides from Dart (nil values use F9 defaults)
    init(dict: [String: Any]?) {
        self.ip = (dict?["ip"] as? String) ?? DashcamConfig.DEFAULT_IP
        self.rtspPort = (dict?["rtspPort"] as? Int) ?? DashcamConfig.DEFAULT_RTSP_PORT
        self.httpPort = (dict?["httpPort"] as? Int) ?? DashcamConfig.DEFAULT_HTTP_PORT
        self.userAgent = (dict?["userAgent"] as? String) ?? DashcamConfig.DEFAULT_USER_AGENT

        let httpBase = "http://\(ip):\(httpPort)"

        // Full URL overrides, or build from effective base + F9 default path
        self.rtspUrl = (dict?["rtspUrl"] as? String) ?? "rtsp://\(ip):\(rtspPort)/"
        self.apiHeartbeat = (dict?["heartbeatEndpoint"] as? String) ?? "\(httpBase)\(DashcamConfig.DEFAULT_HEARTBEAT_PATH)"
        self.apiEnterRecorder = (dict?["enterRecorderEndpoint"] as? String) ?? "\(httpBase)\(DashcamConfig.DEFAULT_ENTER_RECORDER_PATH)"
        self.apiGetMediaInfo = (dict?["getMediaInfoEndpoint"] as? String) ?? "\(httpBase)\(DashcamConfig.DEFAULT_GET_MEDIA_INFO_PATH)"
        self.apiStartLive = (dict?["startLiveEndpoint"] as? String) ?? "\(httpBase)\(DashcamConfig.DEFAULT_START_LIVE_PATH)"
        self.apiSwitchCamera = (dict?["switchCameraEndpoint"] as? String) ?? "\(httpBase)\(DashcamConfig.DEFAULT_SWITCH_CAMERA_PATH)"
    }
}
