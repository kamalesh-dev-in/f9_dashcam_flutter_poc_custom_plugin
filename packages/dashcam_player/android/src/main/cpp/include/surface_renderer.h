#ifndef SURFACE_RENDERER_H
#define SURFACE_RENDERER_H

#include <android/native_window_jni.h>
#include <stdbool.h>
#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration for AVFrame (from FFmpeg)
typedef struct AVFrame AVFrame;

typedef struct SurfaceRenderer SurfaceRenderer;

// Create surface renderer
SurfaceRenderer* surface_renderer_create();

// Set Android Surface
void surface_renderer_set_surface(SurfaceRenderer* renderer, JNIEnv* env, jobject surface);

// Render FFmpeg AVFrame to surface
void surface_renderer_render_frame(SurfaceRenderer* renderer, AVFrame* frame);

// Release renderer resources
void surface_renderer_release(SurfaceRenderer* renderer);

#ifdef __cplusplus
}
#endif

#endif // SURFACE_RENDERER_H
