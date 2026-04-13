package com.dashcam.player

import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import android.view.SurfaceView
import kotlinx.coroutines.*
import java.net.HttpURLConnection
import java.net.URL

/**
 * FFmpeg-based RTSP player for F9 dashcam, adapted for Flutter plugin.
 *
 * Uses FFmpeg's native RTSP client with IPv4-only sockets,
 * bypassing Android's IPv6-first network stack.
 *
 * Events are sent to Flutter via the plugin's EventChannel.
 */
class DashcamNativePlayer(
    private val playerId: Int,
    private val plugin: DashcamPlayerPlugin
) {
    private val nativePlayer = NativeFFmpegPlayer()
    private var playerPtr: Long = 0
    private val scope = CoroutineScope(Dispatchers.IO + Job())
    private var heartbeatJob: Job? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var connectionStartTime: Long = 0
    @Volatile private var isReleased = false
    @Volatile private var hasVideoRenderingStarted = false
    @Volatile private var currentCamera: Int = DashcamConfig.CAMERA_FRONT

    // SurfaceView reference — set when PlatformView is ready
    private var surfaceView: SurfaceView? = null

    // CompletableDeferred to await surface readiness before connect()
    private var surfaceReady = CompletableDeferred<Unit>()

    /**
     * Set the SurfaceView from the PlatformView.
     * Must be called before connect().
     */
    fun setSurfaceView(view: SurfaceView) {
        surfaceView = view
        setupSurface()
    }

    /**
     * Set up player surface with the SurfaceView's holder
     */
    private fun setupSurface() {
        val sv = surfaceView ?: return
        sv.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                log("Surface created callback, initializing native player")
                initNativePlayer(holder)
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                log("Surface changed: ${width}x${height}")
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                log("Surface destroyed")
                // Reset for next surface creation cycle
                surfaceReady = CompletableDeferred()
            }
        })

        // Check if surface is ALREADY valid (callback was missed because
        // surfaceCreated fired before we registered the callback)
        if (sv.holder.surface != null && sv.holder.surface.isValid) {
            log("Surface already valid, initializing immediately (no callback)")
            initNativePlayer(sv.holder)
        }
    }

    /**
     * Initialize the native FFmpeg player with the given surface.
     * Called either from surfaceCreated callback or directly if surface was already ready.
     */
    private fun initNativePlayer(holder: SurfaceHolder) {
        if (playerPtr != 0L) {
            log("Native player already initialized, skipping")
            return
        }
        playerPtr = nativePlayer.nativeCreate(holder.surface)
        if (playerPtr == 0L) {
            log("ERROR: Failed to create native player")
            sendError("Failed to create native player")
        } else {
            log("Native player created: ptr=$playerPtr")
        }
        surfaceReady.complete(Unit)
    }

    /**
     * Connect to dashcam and start streaming.
     *
     * Sequence: ping → enterRecorder → getMediaInfo → heartbeat → startLive → waitPort → RTSP
     */
    suspend fun connect(cameraIndex: Int = DashcamConfig.CAMERA_FRONT): Boolean = withContext(Dispatchers.IO) {
        if (isReleased) {
            log("Cannot connect - player released")
            return@withContext false
        }

        currentCamera = cameraIndex

        // Wait for SurfaceView's surfaceCreated to fire and set playerPtr
        try {
            log("Waiting for surface to be ready...")
            withTimeout(5000L) {
                surfaceReady.await()
            }
            log("Surface is ready, playerPtr=$playerPtr")
        } catch (e: TimeoutCancellationException) {
            log("ERROR: Timed out waiting for surface (5s)")
            sendError("Surface not ready — timed out")
            return@withContext false
        }

        try {
            log("=== Starting FFmpeg connection (camera=$cameraIndex) ===")
            sendStatus("Connecting to dashcam...")

            // Step 0: Verify network connectivity
            log("Step 0: Verifying network connectivity...")
            sendStatus("Verifying network...")
            val isReachable = pingDashcam()
            if (!isReachable) {
                log("WARNING: Dashcam not reachable")
                sendStatus("Dashcam not reachable - check WiFi")
            } else {
                log("Dashcam is reachable")
            }

            // Step 1: Enter recorder mode
            log("Step 1: Enter recorder mode...")
            sendStatus("Entering recorder mode...")
            enterRecorderMode()

            // Step 2: Get media info
            log("Step 2: Get media info...")
            sendStatus("Getting media info...")
            getMediaInfo()

            // Step 3: Start heartbeat BEFORE RTSP
            log("Step 3: Starting heartbeat...")
            startHeartbeat()

            // Step 4: Start live preview (ACTIVATES the stream)
            log("Step 4: Start live preview - ACTIVATING STREAM...")
            sendStatus("Activating stream...")
            val liveStarted = startLivePreview(cameraIndex)
            if (!liveStarted) {
                log("WARNING: Start live preview failed, continuing anyway...")
            }

            // Step 5: Wait for RTSP port
            log("Step 5: Waiting for RTSP port...")
            sendStatus("Waiting for stream activation...")
            val isPortReady = waitForRtspPort(timeoutMs = 5000)
            if (!isPortReady) {
                log("WARNING: RTSP port not responding, trying anyway...")
                sendStatus("Stream slow to activate, attempting connection...")
            }

            // Step 6: Verify native FFmpeg loaded
            log("Step 6: Verifying native FFmpeg...")
            if (playerPtr == 0L) {
                log("ERROR: Native player pointer is NULL")
                stopHeartbeat()
                sendError("Player not initialized - wait for surface")
                return@withContext false
            }

            val testResult = nativePlayer.nativeTest()
            log("Native FFmpeg test: $testResult")
            if (!testResult.contains("working")) {
                log("ERROR: FFmpeg in STUB mode!")
                stopHeartbeat()
                sendError("FFmpeg libraries not loaded")
                return@withContext false
            }

            // Step 7: Connect via FFmpeg RTSP
            log("Step 7: Opening RTSP stream...")
            sendStatus("Opening RTSP stream...")
            connectionStartTime = System.currentTimeMillis()

            val maxRetries = 3
            var connected = false
            for (attempt in 1..maxRetries) {
                log("RTSP attempt $attempt/$maxRetries")
                connected = nativePlayer.nativeConnect(playerPtr, DashcamConfig.RTSP_URL)
                if (connected) {
                    log("RTSP connected on attempt $attempt")
                    break
                }
                if (attempt < maxRetries) {
                    log("RTSP failed, retrying in 1s...")
                    delay(1000)
                }
            }

            if (!connected) {
                log("ERROR: RTSP failed after $maxRetries attempts")
                stopHeartbeat()
                sendError("RTSP connection failed")
                return@withContext false
            }

            // Start playback
            log("Starting FFmpeg playback...")
            nativePlayer.nativeStart(playerPtr)
            log("FFmpeg playback started")

            sendStatus("Playing")

            if (!hasVideoRenderingStarted) {
                hasVideoRenderingStarted = true
                val latency = System.currentTimeMillis() - connectionStartTime
                log("VIDEO STREAMING! Latency: ${latency}ms")
                mainHandler.post {
                    plugin.sendEvent("videoRenderingStarted", mapOf("latencyMs" to latency.toInt()))
                }
            }

            log("=== FFmpeg connection successful ===")
            true

        } catch (e: Exception) {
            val errorMsg = "Connection failed: ${e.javaClass.simpleName} - ${e.message}"
            log("ERROR: $errorMsg")
            stopHeartbeat()
            sendError(errorMsg)
            false
        }
    }

    /**
     * Switch camera via HTTP API and reconnect RTSP.
     *
     * Sequence: stop playback → HTTP switch API → wait for stream restart → reconnect RTSP
     */
    suspend fun switchCamera(camera: Int): Boolean = withContext(Dispatchers.IO) {
        try {
            log("Switching to camera: $camera")
            currentCamera = camera
            sendStatus("Switching camera...")

            // Stop current playback first
            if (playerPtr != 0L) {
                nativePlayer.nativeStop(playerPtr)
            }

            // Call HTTP API to switch camera on the dashcam
            val url = URL("${DashcamConfig.API_SWITCH_CAMERA}$camera")
            log("Camera switch API: $url")
            val switchOk = try {
                with(url.openConnection() as HttpURLConnection) {
                    requestMethod = "GET"
                    connectTimeout = 2000
                    readTimeout = 2000
                    setRequestProperty("User-Agent", DashcamConfig.USER_AGENT)
                    val code = responseCode
                    log("Camera switch API response: HTTP $code")
                    code == 200
                }
            } catch (e: Exception) {
                log("Camera switch API FAILED: ${e.javaClass.simpleName} - ${e.message}")
                false
            }

            if (!switchOk) {
                log("WARNING: Camera switch API failed, attempting reconnect anyway")
            }

            // Wait for RTSP stream to restart on new camera
            delay(500)
            val portReady = waitForRtspPort(timeoutMs = 5000)
            if (!portReady) {
                log("WARNING: RTSP port not ready after camera switch, trying anyway")
            }

            // Reconnect RTSP with retries
            val maxRetries = 3
            var connected = false
            for (attempt in 1..maxRetries) {
                log("Camera reconnect attempt $attempt/$maxRetries")
                connected = nativePlayer.nativeConnect(playerPtr, DashcamConfig.RTSP_URL)
                if (connected) {
                    log("Camera reconnect succeeded on attempt $attempt")
                    break
                }
                if (attempt < maxRetries) {
                    log("Camera reconnect failed, retrying in 1s...")
                    delay(1000)
                }
            }

            if (connected) {
                nativePlayer.nativeStart(playerPtr)
                sendStatus("Camera $camera active")
                log("Camera switch complete: camera $camera playing")
            } else {
                log("ERROR: Camera switch failed — could not reconnect RTSP")
                sendError("Camera switch failed — stream disconnected")
            }
            connected

        } catch (e: Exception) {
            log("Camera switch error: ${e.javaClass.simpleName} - ${e.message}")
            sendError("Camera switch error: ${e.message}")
            false
        }
    }

    /**
     * Stop playback
     */
    fun stop() {
        try {
            if (!isReleased && playerPtr != 0L) {
                log("Stopping FFmpeg playback")
                stopHeartbeat()
                nativePlayer.nativeStop(playerPtr)
            }
        } catch (e: Exception) {
            log("Error stopping: ${e.message}")
        }
    }

    /**
     * Release all resources
     */
    fun release() {
        try {
            log("Releasing FFmpeg player")
            isReleased = true
            stopHeartbeat()
            // Cancel pending surface wait if any
            surfaceReady.cancel()
            if (playerPtr != 0L) {
                nativePlayer.nativeRelease(playerPtr)
                playerPtr = 0
            }
            scope.cancel()
        } catch (e: Exception) {
            log("Error releasing: ${e.message}")
        }
    }

    // === Private HTTP API Functions ===

    private suspend fun pingDashcam(): Boolean = withContext(Dispatchers.IO) {
        try {
            val url = URL(DashcamConfig.API_HEARTBEAT)
            log("Ping: $url")
            with(url.openConnection() as HttpURLConnection) {
                requestMethod = "GET"
                connectTimeout = 3000
                readTimeout = 3000
                val code = responseCode
                log("Ping response: HTTP $code")
                code == 200
            }
        } catch (e: Exception) {
            log("Ping FAILED: ${e.javaClass.simpleName} - ${e.message}")
            false
        }
    }

    private suspend fun enterRecorderMode(): Boolean = withContext(Dispatchers.IO) {
        try {
            val url = URL(DashcamConfig.API_ENTER_RECORDER)
            log("EnterRecorder: $url")
            with(url.openConnection() as HttpURLConnection) {
                requestMethod = "GET"
                connectTimeout = 2000
                readTimeout = 2000
                setRequestProperty("User-Agent", DashcamConfig.USER_AGENT)
                val code = responseCode
                log("EnterRecorder response: HTTP $code")
                code == 200
            }
        } catch (e: Exception) {
            log("EnterRecorder FAILED: ${e.javaClass.simpleName} - ${e.message}")
            false
        }
    }

    private suspend fun getMediaInfo(): Boolean = withContext(Dispatchers.IO) {
        try {
            val url = URL(DashcamConfig.API_GET_MEDIA_INFO)
            log("GetMediaInfo: $url")
            with(url.openConnection() as HttpURLConnection) {
                requestMethod = "GET"
                connectTimeout = 2000
                readTimeout = 2000
                setRequestProperty("User-Agent", DashcamConfig.USER_AGENT)
                val code = responseCode
                log("GetMediaInfo response: HTTP $code")
                code == 200
            }
        } catch (e: Exception) {
            log("GetMediaInfo FAILED: ${e.javaClass.simpleName} - ${e.message}")
            true // Non-critical
        }
    }

    private suspend fun startLivePreview(camIndex: Int = 0): Boolean = withContext(Dispatchers.IO) {
        try {
            val url = URL("${DashcamConfig.API_START_LIVE}$camIndex")
            log("StartLive: $url")
            with(url.openConnection() as HttpURLConnection) {
                requestMethod = "GET"
                connectTimeout = 2000
                readTimeout = 2000
                setRequestProperty("User-Agent", DashcamConfig.USER_AGENT)
                val code = responseCode
                log("StartLive response: HTTP $code")
                code == 200
            }
        } catch (e: Exception) {
            log("StartLive FAILED: ${e.javaClass.simpleName} - ${e.message}")
            false
        }
    }

    private suspend fun waitForRtspPort(timeoutMs: Long = 5000): Boolean = withContext(Dispatchers.IO) {
        val startTime = System.currentTimeMillis()
        var attempts = 0
        while (System.currentTimeMillis() - startTime < timeoutMs) {
            attempts++
            try {
                val socket = java.net.Socket()
                socket.connect(java.net.InetSocketAddress(DashcamConfig.DASHCAM_IP, DashcamConfig.RTSP_PORT), 500)
                socket.close()
                log("RTSP port ready after $attempts attempts")
                return@withContext true
            } catch (e: Exception) {
                delay(300)
            }
        }
        log("RTSP port not ready after $attempts attempts")
        false
    }

    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = scope.launch {
            while (isActive && !isReleased) {
                delay(5000)
                try {
                    val url = URL(DashcamConfig.API_HEARTBEAT)
                    with(url.openConnection() as HttpURLConnection) {
                        requestMethod = "GET"
                        connectTimeout = 2000
                        readTimeout = 2000
                        if (responseCode == 200) {
                            log("Heartbeat: OK")
                        }
                    }
                } catch (e: Exception) {
                    log("Heartbeat: ${e.javaClass.simpleName}")
                }
            }
        }
    }

    private fun stopHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = null
    }

    // === Event Helpers ===

    private fun sendStatus(message: String) {
        mainHandler.post {
            plugin.sendEvent("statusChanged", mapOf("message" to message))
        }
    }

    private fun sendError(message: String) {
        mainHandler.post {
            plugin.sendEvent("error", mapOf("message" to message))
        }
    }

    private fun log(message: String) {
        android.util.Log.d("DashcamPlayer[$playerId]", message)
    }
}
