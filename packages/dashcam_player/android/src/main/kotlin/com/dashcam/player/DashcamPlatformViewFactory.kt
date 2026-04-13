package com.dashcam.player

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory that creates DashcamPlatformView instances when Flutter requests an AndroidView.
 */
class DashcamPlatformViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): DashcamPlatformView {
        return DashcamPlatformView(context, viewId)
    }
}
