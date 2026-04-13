package com.dashcam.player

import android.view.Surface

/**
 * JNI bridge to native FFmpeg player.
 *
 * This class provides native methods that call into C++ code
 * using FFmpeg libraries for RTSP streaming with IPv4-only sockets.
 */
class NativeFFmpegPlayer {

    /**
     * Native test method to verify JNI is working
     */
    external fun nativeTest(): String

    /**
     * Create native player instance with surface
     * @return Pointer to native player (as Long)
     */
    external fun nativeCreate(surface: Surface): Long

    /**
     * Connect to RTSP stream
     * @param playerPtr Native player pointer
     * @param rtspUrl RTSP URL to connect to
     * @return true if connection succeeded
     */
    external fun nativeConnect(playerPtr: Long, rtspUrl: String): Boolean

    /**
     * Start playback
     * @param playerPtr Native player pointer
     */
    external fun nativeStart(playerPtr: Long)

    /**
     * Stop playback
     * @param playerPtr Native player pointer
     */
    external fun nativeStop(playerPtr: Long)

    /**
     * Release native player resources
     * @param playerPtr Native player pointer
     */
    external fun nativeRelease(playerPtr: Long)

    companion object {
        init {
            System.loadLibrary("dashcamplayer")
        }
    }
}
