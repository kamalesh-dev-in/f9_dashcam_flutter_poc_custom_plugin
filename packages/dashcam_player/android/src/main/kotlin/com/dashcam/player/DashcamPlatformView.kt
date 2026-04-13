package com.dashcam.player

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import android.view.SurfaceView
import io.flutter.plugin.platform.PlatformView

/**
 * PlatformView that hosts a SurfaceView for FFmpeg video rendering.
 *
 * The native C++ code renders directly to this SurfaceView's ANativeWindow,
 * bypassing Flutter's rendering pipeline for minimal latency.
 */
class DashcamPlatformView(
    context: Context,
    private val viewId: Int
) : PlatformView {

    private val surfaceView: SurfaceView = SurfaceView(context)

    companion object {
        private val views = mutableMapOf<Int, DashcamPlatformView>()

        /** Get a PlatformView by its Flutter view ID */
        fun get(id: Int): DashcamPlatformView? = views[id]
    }

    init {
        views[viewId] = this
        surfaceView.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        surfaceView.keepScreenOn = true
    }

    /** Expose the SurfaceView so the native player can use its surface */
    fun getSurfaceView(): SurfaceView = surfaceView

    override fun getView(): View = surfaceView

    override fun dispose() {
        views.remove(viewId)
    }
}
