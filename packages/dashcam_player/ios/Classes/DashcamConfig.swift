import Foundation

struct DashcamConfig {
    // Dashcam network
    static let DASHCAM_IP = "192.168.169.1"
    static let RTSP_PORT = 554
    static let RTSP_URL = "rtsp://\(DASHCAM_IP):\(RTSP_PORT)/"

    // Camera indices
    static let CAMERA_FRONT = 0
    static let CAMERA_REAR = 1
    static let CAMERA_PIP = 2

    // User agent for HTTP requests
    static let USER_AGENT = "HiCamera"

    // HTTP API endpoints (same as Android)
    static let API_HEARTBEAT = "http://\(DASHCAM_IP)/app/getparamvalue?param=rec"
    static let API_ENTER_RECORDER = "http://\(DASHCAM_IP)/app/enterrecorder"
    static let API_GET_MEDIA_INFO = "http://\(DASHCAM_IP)/app/getmediainfo"
    static let API_START_LIVE = "http://\(DASHCAM_IP)/?custom=1&cmd=2015&par="
    static let API_SWITCH_CAMERA = "http://\(DASHCAM_IP)/app/setparamvalue?param=switchcam&value="

    // Camera names for UI
    static let cameraNames = ["Front", "Rear", "PiP"]

    // RTSP stream parameters
    static let width = 1920
    static let height = 1080
    static let fps = 30
}
