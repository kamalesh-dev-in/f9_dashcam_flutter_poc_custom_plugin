#ifndef METAL_RENDERER_H
#define METAL_RENDERER_H

#include <stdint.h>

// Forward declarations
typedef struct AVFrame AVFrame;
typedef struct MetalRenderer MetalRenderer;

// Create a Metal renderer with an MTKView
MetalRenderer* metal_renderer_create(void* metalView);

// Upload an FFmpeg AVFrame to Metal texture (called from background thread)
void metal_renderer_render_frame(MetalRenderer* renderer, AVFrame* frame);

// Draw the current texture to screen (called from main thread via MTKView delegate)
void metal_renderer_draw(MetalRenderer* renderer);

// Release all rendering resources
void metal_renderer_release(MetalRenderer* renderer);

#endif // METAL_RENDERER_H
