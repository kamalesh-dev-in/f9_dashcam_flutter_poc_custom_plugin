#include "surface_renderer.h"
#include <android/log.h>
#include <stdlib.h>
#include <string.h>
#include <android/native_window_jni.h>

#define LOG_TAG "SurfaceRenderer"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

// Check if FFmpeg is available
#if defined(HAVE_FFMPEG)
extern "C" {
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
}
#endif

// Surface renderer structure
struct SurfaceRenderer {
    ANativeWindow* window;
    int width;
    int height;
#if defined(HAVE_FFMPEG)
    struct SwsContext* sws_ctx;
    uint8_t* rgb_buffer;
    int rgb_linesize;
#endif
};

// Create surface renderer
SurfaceRenderer* surface_renderer_create() {
    LOGI("Creating SurfaceRenderer");

    SurfaceRenderer* renderer = (SurfaceRenderer*)malloc(sizeof(SurfaceRenderer));
    if (!renderer) {
        LOGE("Failed to allocate SurfaceRenderer");
        return nullptr;
    }

    memset(renderer, 0, sizeof(SurfaceRenderer));
    renderer->window = nullptr;
    renderer->width = 0;
    renderer->height = 0;
#if defined(HAVE_FFMPEG)
    renderer->sws_ctx = nullptr;
    renderer->rgb_buffer = nullptr;
    renderer->rgb_linesize = 0;
#endif

    return renderer;
}

// Set Android Surface
void surface_renderer_set_surface(SurfaceRenderer* renderer, JNIEnv* env, jobject surface) {
    LOGI("Setting Android Surface");

    if (!renderer) return;

    // Release old window if exists
    if (renderer->window) {
        ANativeWindow_release(renderer->window);
        renderer->window = nullptr;
    }

    // Get native window from Java surface
    renderer->window = ANativeWindow_fromSurface(env, surface);

    if (renderer->window) {
        LOGI("Surface set successfully");
    } else {
        LOGE("Failed to get native window");
    }
}

// Render FFmpeg AVFrame to surface
void surface_renderer_render_frame(SurfaceRenderer* renderer, AVFrame* frame) {
#if defined(HAVE_FFMPEG)
    if (!renderer || !renderer->window || !frame) {
        return;
    }

    // Update window geometry if frame size changed
    if (renderer->width != frame->width || renderer->height != frame->height) {
        renderer->width = frame->width;
        renderer->height = frame->height;

        ANativeWindow_setBuffersGeometry(renderer->window,
                                          frame->width,
                                          frame->height,
                                          WINDOW_FORMAT_RGBA_8888);

        // Free old buffer
        if (renderer->rgb_buffer) {
            av_free(renderer->rgb_buffer);
            renderer->rgb_buffer = nullptr;
        }

        // Free old sws context
        if (renderer->sws_ctx) {
            sws_freeContext(renderer->sws_ctx);
            renderer->sws_ctx = nullptr;
        }

        // Calculate linesize (aligned to 32 bytes for SIMD)
        renderer->rgb_linesize = ((frame->width * 4 + 31) / 32) * 32;  // 4 bytes per RGBA pixel

        // Allocate buffer manually using av_malloc (guarantees 32-byte alignment)
        size_t buffer_size = (size_t)renderer->rgb_linesize * frame->height;
        renderer->rgb_buffer = (uint8_t*)av_malloc(buffer_size);

        if (!renderer->rgb_buffer) {
            LOGE("Failed to allocate RGB buffer: size=%zu bytes", buffer_size);
            renderer->rgb_linesize = 0;
            return;
        }

        LOGI("RGB buffer allocated: size=%zu bytes, linesize=%d, width=%d, height=%d",
             buffer_size, renderer->rgb_linesize, frame->width, frame->height);
        LOGI("Updated surface geometry: %dx%d", frame->width, frame->height);
    }

    // Create swscale context if needed
    if (!renderer->sws_ctx) {
        renderer->sws_ctx = sws_getContext(
            frame->width, frame->height, (AVPixelFormat)frame->format,
            renderer->width, renderer->height, AV_PIX_FMT_RGBA,
            SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);
    }

    if (!renderer->sws_ctx) {
        LOGE("Failed to create swscale context");
        return;
    }

    // Lock window for rendering
    ANativeWindow_Buffer buffer;
    if (ANativeWindow_lock(renderer->window, &buffer, nullptr) < 0) {
        LOGE("Failed to lock window");
        return;
    }

    // Convert frame to RGBA
    int scale_ret = sws_scale(renderer->sws_ctx,
              frame->data, frame->linesize,
              0, frame->height,
              &renderer->rgb_buffer, &renderer->rgb_linesize);

    if (scale_ret < 0) {
        LOGE("sws_scale failed: ret=%d", scale_ret);
    } else if (scale_ret != frame->height) {
        LOGW("sws_scale partial: returned %d, expected %d", scale_ret, frame->height);
    }

    // Copy to window buffer
    uint8_t* dst = (uint8_t*)buffer.bits;
    uint8_t* src = renderer->rgb_buffer;
    int src_linesize = renderer->rgb_linesize;
    int dst_linesize = buffer.stride * 4; // RGBA = 4 bytes per pixel

    // Log rendering info for debugging
    LOGI("Rendering frame: width=%d, height=%d, src_linesize=%d, dst_linesize=%d",
         renderer->width, renderer->height, src_linesize, dst_linesize);

    for (int y = 0; y < renderer->height; y++) {
        memcpy(dst + y * dst_linesize,
               src + y * src_linesize,
               src_linesize);  // FIXED: Use actual source line size, not width * 4
    }

    // Unlock and post
    ANativeWindow_unlockAndPost(renderer->window);
#else
    // Stub mode - no rendering
    (void)renderer;
    (void)frame;
#endif
}

// Release resources
void surface_renderer_release(SurfaceRenderer* renderer) {
    LOGI("Releasing SurfaceRenderer");

    if (renderer) {
#if defined(HAVE_FFMPEG)
        if (renderer->sws_ctx) {
            sws_freeContext(renderer->sws_ctx);
        }
        if (renderer->rgb_buffer) {
            av_freep(&renderer->rgb_buffer);
        }
#endif
        if (renderer->window) {
            ANativeWindow_release(renderer->window);
        }
        free(renderer);
    }
}
