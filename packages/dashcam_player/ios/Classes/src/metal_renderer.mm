#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include "metal_renderer.h"
#include <stdlib.h>
#include <string.h>
#include <os/log.h>

#define LOG_TAG "MetalRenderer"
static os_log_t rendererLog = os_log_create("com.dashcam.player", LOG_TAG);
#define LOGI(fmt, ...) os_log_info(rendererLog, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(rendererLog, fmt, ##__VA_ARGS__)
#define LOGD(fmt, ...) os_log_debug(rendererLog, fmt, ##__VA_ARGS__)

#if defined(HAVE_FFMPEG)
extern "C" {
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
#include <libavutil/frame.h>
}
#endif

// Inline Metal Shading Language shader
static const char* kShaderSource = R"(
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
    // Full-screen quad: 4 vertices as triangle strip
    float2 pos[4] = {
        float2(-1, -1), float2(1, -1),
        float2(-1,  1), float2(1,  1)
    };
    float2 uv[4] = {
        float2(0, 1), float2(1, 1),
        float2(0, 0), float2(1, 0)
    };
    VertexOut out;
    out.position = float4(pos[vertexID], 0, 1);
    out.texCoord = uv[vertexID];
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float, access::sample> tex [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    return tex.sample(s, in.texCoord);
}
)";

// Metal renderer structure
struct MetalRenderer {
    id<MTLDevice>               device;
    id<MTLCommandQueue>         commandQueue;
    id<MTLTexture>              texture;
    id<MTLRenderPipelineState>  pipelineState;
    MTKView*                    metalView;
    int                         width;
    int                         height;
    bool                        frameReady;

#if defined(HAVE_FFMPEG)
    struct SwsContext*    sws_ctx;
    uint8_t*             rgb_buffer;
    int                  rgb_linesize;
#endif
};

// Create the render pipeline (full-screen textured quad)
static bool create_pipeline(MetalRenderer* renderer) {
    NSError* error = nil;
    id<MTLLibrary> library = [renderer->device newLibraryWithSource:@(kShaderSource)
                                                            options:nil
                                                              error:&error];
    if (!library) {
        LOGE("Failed to compile Metal shaders: %s", error.localizedDescription.UTF8String);
        return false;
    }

    id<MTLFunction> vertexFunc = [library newFunctionWithName:@"vertexShader"];
    id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragmentShader"];
    if (!vertexFunc || !fragmentFunc) {
        LOGE("Failed to find shader functions");
        return false;
    }

    MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction = vertexFunc;
    desc.fragmentFunction = fragmentFunc;
    desc.colorAttachments[0].pixelFormat = renderer->metalView.colorPixelFormat;

    renderer->pipelineState = [renderer->device newRenderPipelineStateWithDescriptor:desc
                                                                               error:&error];
    if (!renderer->pipelineState) {
        LOGE("Failed to create render pipeline: %s", error.localizedDescription.UTF8String);
        return false;
    }

    LOGI("Metal render pipeline created");
    return true;
}

// Create Metal renderer
MetalRenderer* metal_renderer_create(void* viewPtr) {
    LOGI("Creating MetalRenderer");

    MTKView* view = (__bridge MTKView*)viewPtr;
    if (!view) {
        LOGE("MTKView is nil");
        return nullptr;
    }

    MetalRenderer* renderer = new MetalRenderer();
    memset(renderer, 0, sizeof(MetalRenderer));

    renderer->metalView = view;
    renderer->device = view.device;
    renderer->commandQueue = [renderer->device newCommandQueue];
    renderer->texture = nil;
    renderer->pipelineState = nil;
    renderer->width = 0;
    renderer->height = 0;
    renderer->frameReady = false;

#if defined(HAVE_FFMPEG)
    renderer->sws_ctx = nullptr;
    renderer->rgb_buffer = nullptr;
    renderer->rgb_linesize = 0;
#endif

    // Create the render pipeline for drawing textured quads
    if (!create_pipeline(renderer)) {
        delete renderer;
        return nullptr;
    }

    LOGI("Metal renderer created with device: %s", renderer->device.name.UTF8String);
    return renderer;
}

// Upload FFmpeg AVFrame to Metal texture (called from background FFmpeg thread)
void metal_renderer_render_frame(MetalRenderer* renderer, AVFrame* frame) {
#if defined(HAVE_FFMPEG)
    if (!renderer || !renderer->metalView || !frame) {
        return;
    }

    // Update texture if frame size changed
    if (!renderer->texture || renderer->width != frame->width || renderer->height != frame->height) {
        renderer->width = frame->width;
        renderer->height = frame->height;

        // Create Metal texture — use BGRA to match iOS Metal byte order
        MTLTextureDescriptor* desc = [[MTLTextureDescriptor alloc] init];
        desc.pixelFormat = MTLPixelFormatBGRA8Unorm;
        desc.width = frame->width;
        desc.height = frame->height;
        desc.usage = MTLTextureUsageShaderRead;

        renderer->texture = [renderer->device newTextureWithDescriptor:desc];

        if (!renderer->texture) {
            LOGE("Failed to create Metal texture");
            return;
        }

        // Free old buffers
        if (renderer->rgb_buffer) {
            av_free(renderer->rgb_buffer);
            renderer->rgb_buffer = nullptr;
        }
        if (renderer->sws_ctx) {
            sws_freeContext(renderer->sws_ctx);
            renderer->sws_ctx = nullptr;
        }

        // Allocate RGB buffer with 32-byte alignment (same as Android)
        renderer->rgb_linesize = ((frame->width * 4 + 31) / 32) * 32;
        size_t buffer_size = (size_t)renderer->rgb_linesize * frame->height;
        renderer->rgb_buffer = (uint8_t*)av_malloc(buffer_size);

        if (!renderer->rgb_buffer) {
            LOGE("Failed to allocate RGB buffer: size=%zu bytes", buffer_size);
            renderer->rgb_linesize = 0;
            return;
        }

        LOGI("Metal texture created: %dx%d, buffer=%zu bytes",
             frame->width, frame->height, buffer_size);
    }

    // Create swscale context for YUV → BGRA (fixes blue tint on iOS)
    if (!renderer->sws_ctx) {
        renderer->sws_ctx = sws_getContext(
            frame->width, frame->height, (AVPixelFormat)frame->format,
            renderer->width, renderer->height, AV_PIX_FMT_BGRA,
            SWS_FAST_BILINEAR, nullptr, nullptr, nullptr
        );
    }

    if (!renderer->sws_ctx) {
        LOGE("Failed to create swscale context");
        return;
    }

    // Convert YUV → BGRA
    int scale_ret = sws_scale(renderer->sws_ctx,
        frame->data, frame->linesize,
        0, frame->height,
        &renderer->rgb_buffer, &renderer->rgb_linesize
    );

    if (scale_ret < 0) {
        LOGE("sws_scale failed: ret=%d", scale_ret);
        return;
    }

    // Copy BGRA data into Metal texture (safe on background thread)
    MTLRegion region = MTLRegionMake2D(0, 0, renderer->width, renderer->height);
    [renderer->texture replaceRegion:region
                         mipmapLevel:0
                           withBytes:renderer->rgb_buffer
                         bytesPerRow:renderer->rgb_linesize];

    // Mark frame as ready for drawing
    renderer->frameReady = true;

    // Trigger draw on main thread (display-synced via MTKView)
    dispatch_async(dispatch_get_main_queue(), ^{
        [renderer->metalView setNeedsDisplay];
    });

#else
    // Stub mode
    (void)renderer;
    (void)frame;
#endif
}

// Draw current texture to screen (called from main thread via MTKView delegate)
void metal_renderer_draw(MetalRenderer* renderer) {
    if (!renderer || !renderer->texture || !renderer->metalView || !renderer->pipelineState) {
        return;
    }

    if (!renderer->frameReady) {
        return;
    }
    renderer->frameReady = false;

    @autoreleasepool {
        MTKView* view = renderer->metalView;
        id<CAMetalDrawable> drawable = view.currentDrawable;

        if (drawable && drawable.texture) {
            id<MTLCommandBuffer> commandBuffer = [renderer->commandQueue commandBuffer];

            MTLRenderPassDescriptor* renderPassDesc = view.currentRenderPassDescriptor;
            renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
            renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

            id<MTLRenderCommandEncoder> encoder = [commandBuffer
                renderCommandEncoderWithDescriptor:renderPassDesc];

            [encoder setRenderPipelineState:renderer->pipelineState];
            [encoder setFragmentTexture:renderer->texture atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
            [encoder endEncoding];

            [commandBuffer presentDrawable:drawable];
            [commandBuffer commit];
        }
    }
}

// Release resources
void metal_renderer_release(MetalRenderer* renderer) {
    if (!renderer) return;

    LOGI("Releasing MetalRenderer");

#if defined(HAVE_FFMPEG)
    if (renderer->sws_ctx) {
        sws_freeContext(renderer->sws_ctx);
    }
    if (renderer->rgb_buffer) {
        av_freep(&renderer->rgb_buffer);
    }
#endif

    // Metal objects are auto-released via ARC
    renderer->texture = nil;
    renderer->pipelineState = nil;
    renderer->commandQueue = nil;

    delete renderer;
    LOGI("MetalRenderer released");
}
