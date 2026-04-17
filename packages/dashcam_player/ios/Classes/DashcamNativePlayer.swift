import Foundation

/// FFmpeg-based RTSP player for F9 dashcam on iOS.
///
/// Same 7-step connection sequence as Android:
/// ping → enterRecorder → getMediaInfo → heartbeat → startLive → waitPort → RTSP
class DashcamNativePlayer {

    private let playerId: Int
    private let plugin: DashcamPlayerPlugin
    private let bridge = DashcamNativeBridge()
    private var playerPtr: NSNumber?

    private var heartbeatTimer: Timer?
    private var isReleased = false
    private var shouldStopConnecting = false
    private var currentCamera: Int = DashcamConfig.CAMERA_FRONT

    init(playerId: Int, plugin: DashcamPlayerPlugin) {
        self.playerId = playerId
        self.plugin = plugin
    }

    // MARK: - Public API

    /// Set the MTKView for rendering. Called when PlatformView is ready.
    func setMetalView(_ view: UIView, platformView: DashcamPlatformView? = nil) {
        if playerPtr != nil {
            log("Native player already created, skipping")
            return
        }
        playerPtr = bridge.nativeCreate(with: view)
        if playerPtr?.int64Value == 0 {
            log("ERROR: Failed to create native player")
            sendError("Failed to create native player")
        } else {
            log("Native player created: ptr=\(playerPtr!)")

            // Pass bridge to PlatformView for MTKView delegate draw calls
            if let pv = platformView {
                pv.setBridge(bridge)
            }
        }
    }

    /// Connect to dashcam and start streaming.
    func connect(cameraIndex: Int = DashcamConfig.CAMERA_FRONT,
                 completion: @escaping (Bool) -> Void) {
        if isReleased {
            log("Cannot connect - player released")
            completion(false)
            return
        }

        // Signal any running connection/switch to stop
        shouldStopConnecting = true
        currentCamera = cameraIndex

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            // Wait for old connection/switch loop to exit
            Thread.sleep(forTimeInterval: 0.5)
            self.shouldStopConnecting = false
            let success = self.doConnect(cameraIndex: cameraIndex)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    /// Switch camera via HTTP API and reconnect RTSP.
    func switchCamera(camera: Int, completion: @escaping (Bool) -> Void) {
        // Signal any running connection/switch to stop
        shouldStopConnecting = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            // Wait for old connection loop to exit
            Thread.sleep(forTimeInterval: 0.5)
            self.shouldStopConnecting = false
            let success = self.doSwitchCamera(camera: camera)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    /// Stop playback.
    func stop() {
        guard !isReleased, let ptr = playerPtr, ptr.int64Value != 0 else { return }
        log("Stopping FFmpeg playback")
        shouldStopConnecting = true
        stopHeartbeat()
        bridge.nativeStop(ptr)
    }

    /// Release all resources.
    func release() {
        guard !isReleased else { return }
        log("Releasing FFmpeg player")
        isReleased = true
        shouldStopConnecting = true
        stopHeartbeat()
        if let ptr = playerPtr, ptr.int64Value != 0 {
            bridge.nativeRelease(ptr)
            playerPtr = nil
        }
    }

    // MARK: - Connection Sequence (same as Android)

    private func doConnect(cameraIndex: Int) -> Bool {
        log("=== Starting FFmpeg connection (camera=\(cameraIndex)) ===")

        var attemptNumber = 0

        while !isReleased && !shouldStopConnecting {
            attemptNumber += 1
            let verbose = attemptNumber <= 3 || attemptNumber % 5 == 0

            if verbose {
                log("=== Connection attempt \(attemptNumber) ===")
            }
            sendStatus("Connecting... (attempt \(attemptNumber))")

            // Step 0: Verify network
            if verbose { log("Step 0: Verifying network connectivity...") }
            let isReachable = pingDashcam()
            if !isReachable {
                if verbose { log("WARNING: Dashcam not reachable") }
            }

            if isReleased || shouldStopConnecting { break }

            // Step 1: Enter recorder mode
            if verbose { log("Step 1: Enter recorder mode...") }
            _ = enterRecorderMode()

            // Step 2: Get media info
            if verbose { log("Step 2: Get media info...") }
            _ = getMediaInfo()

            if isReleased || shouldStopConnecting { break }

            // Step 3: Start heartbeat
            if verbose { log("Step 3: Starting heartbeat...") }
            startHeartbeat()

            // Step 4: Start live preview
            if verbose { log("Step 4: Start live preview - ACTIVATING STREAM...") }
            sendStatus("Activating stream...")
            let liveStarted = startLivePreview(cameraIndex: cameraIndex)
            if !liveStarted && verbose {
                log("WARNING: Start live preview failed, continuing anyway...")
            }

            // Step 5: Wait for RTSP port
            if verbose { log("Step 5: Waiting for RTSP port...") }
            let portReady = waitForRtspPort(timeoutMs: 5000)
            if !portReady && verbose {
                log("WARNING: RTSP port not responding, trying anyway...")
            }

            if isReleased || shouldStopConnecting { break }

            // Step 6: Verify native player
            guard let ptr = playerPtr, ptr.int64Value != 0 else {
                log("ERROR: Native player pointer is NULL")
                stopHeartbeat()
                sendError("Player not initialized")
                return false
            }

            if attemptNumber == 1 {
                let testResult = bridge.nativeTest()
                log("Native FFmpeg test: \(testResult)")
                if !testResult.contains("working") {
                    log("ERROR: FFmpeg in STUB mode!")
                    stopHeartbeat()
                    sendError("FFmpeg libraries not loaded")
                    return false
                }
            }

            if isReleased || shouldStopConnecting { break }

            // Step 7: Connect via FFmpeg RTSP (inner 3-retry)
            if verbose { log("Step 7: Opening RTSP stream...") }
            sendStatus("Opening RTSP stream...")

            var connected = false
            for rtspAttempt in 1...3 {
                if isReleased || shouldStopConnecting { break }
                if verbose { log("RTSP attempt \(rtspAttempt)/3") }
                connected = bridge.nativeConnect(ptr, url: DashcamConfig.RTSP_URL)
                if connected {
                    log("RTSP connected on attempt \(rtspAttempt)")
                    break
                }
                if rtspAttempt < 3 {
                    Thread.sleep(forTimeInterval: 1.0)
                }
            }

            if connected {
                // Start playback
                log("Starting FFmpeg playback...")
                bridge.nativeStart(ptr)
                log("FFmpeg playback started")

                sendStatus("Playing")
                log("=== FFmpeg connection successful on attempt \(attemptNumber) ===")
                return true
            }

            // Failed — stop heartbeat before retry
            stopHeartbeat()

            // Wait 3 seconds before next full attempt (check cancellation every 0.5s)
            log("Attempt \(attemptNumber) failed, retrying in 3s...")
            sendStatus("Retrying in 3s... (attempt \(attemptNumber))")
            for _ in 0..<6 {
                if isReleased || shouldStopConnecting { return false }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        log("Connection loop stopped")
        return false
    }

    private func doSwitchCamera(camera: Int) -> Bool {
        log("Switching to camera: \(camera)")
        currentCamera = camera
        sendStatus("Switching camera...")

        // Stop current playback
        if let ptr = playerPtr, ptr.int64Value != 0 {
            bridge.nativeStop(ptr)
        }

        // Call HTTP API to switch camera
        let urlString = "\(DashcamConfig.API_SWITCH_CAMERA)\(camera)"
        let switchOk = httpGet(urlString)
        if !switchOk {
            log("WARNING: Camera switch API failed, attempting reconnect anyway")
        }

        // Wait for stream restart
        Thread.sleep(forTimeInterval: 0.5)
        let portReady = waitForRtspPort(timeoutMs: 5000)
        if !portReady {
            log("WARNING: RTSP port not ready after camera switch")
        }

        // Reconnect RTSP with infinite retry
        guard let ptr = playerPtr, ptr.int64Value != 0 else {
            sendError("Player not available")
            return false
        }

        var attemptNumber = 0
        while !isReleased && !shouldStopConnecting {
            attemptNumber += 1
            let connected = bridge.nativeConnect(ptr, url: DashcamConfig.RTSP_URL)
            if connected {
                bridge.nativeStart(ptr)
                sendStatus("Camera \(camera) active")
                log("Camera switch complete: camera \(camera) playing")
                return true
            }

            log("Camera reconnect attempt \(attemptNumber) failed, retrying in 3s...")
            sendStatus("Reconnecting camera... (attempt \(attemptNumber))")
            for _ in 0..<6 {
                if isReleased || shouldStopConnecting { return false }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        log("Camera switch cancelled")
        sendError("Camera switch cancelled")
        return false
    }

    // MARK: - HTTP API Helpers (same as Android)

    private func pingDashcam() -> Bool {
        return httpGet(DashcamConfig.API_HEARTBEAT)
    }

    private func enterRecorderMode() -> Bool {
        return httpGet(DashcamConfig.API_ENTER_RECORDER)
    }

    private func getMediaInfo() -> Bool {
        // Non-critical, return true even on failure
        _ = httpGet(DashcamConfig.API_GET_MEDIA_INFO)
        return true
    }

    private func startLivePreview(cameraIndex: Int) -> Bool {
        let url = "\(DashcamConfig.API_START_LIVE)\(cameraIndex)"
        return httpGet(url)
    }

    private func waitForRtspPort(timeoutMs: Int) -> Bool {
        let startTime = Date()
        var attempts = 0

        while Date().timeIntervalSince(startTime) < Double(timeoutMs) / 1000.0 {
            attempts += 1
            if checkTcpPort(host: DashcamConfig.DASHCAM_IP, port: DashcamConfig.RTSP_PORT, timeoutMs: 500) {
                log("RTSP port ready after \(attempts) attempts")
                return true
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        log("RTSP port not ready after \(attempts) attempts")
        return false
    }

    private func httpGet(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        request.setValue(DashcamConfig.USER_AGENT, forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                NSLog("DashcamPlayer[\(self.playerId)]: HTTP GET \(urlString) FAILED: \(error.localizedDescription)")
            } else if let httpResponse = response as? HTTPURLResponse {
                success = httpResponse.statusCode == 200
                NSLog("DashcamPlayer[\(self.playerId)]: HTTP GET \(urlString) → \(httpResponse.statusCode)")
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()
        return success
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isReleased else { return }
            self.httpGet(DashcamConfig.API_HEARTBEAT)
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Event Helpers

    private func sendStatus(_ message: String) {
        DispatchQueue.main.async {
            self.plugin.sendEvent("statusChanged", data: ["message": message])
        }
    }

    private func sendError(_ message: String) {
        DispatchQueue.main.async {
            self.plugin.sendEvent("error", data: ["message": message])
        }
    }

    private func log(_ message: String) {
        NSLog("DashcamPlayer[\(playerId)]: \(message)")
    }
}

// MARK: - Simple TCP Socket Helper

private func checkTcpPort(host: String, port: Int, timeoutMs: Int) -> Bool {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(port).bigEndian
    inet_pton(AF_INET, host, &addr.sin_addr)

    let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    if sock < 0 { return false }
    defer { Darwin.close(sock) }

    // Set send timeout for connect
    var tv = timeval(tv_sec: timeoutMs / 1000, tv_usec: Int32((timeoutMs % 1000) * 1000))
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    let result = withUnsafePointer(to: &addr) { ptr in
        Darwin.connect(sock, UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_in>.size))
    }

    return result == 0
}
