#import "DashcamNativeBridge.h"
#include "ffmpeg_player.h"
#include "metal_renderer.h"

@implementation DashcamNativeBridge {
    void* _rendererPtr;
}

- (NSString*)nativeTest {
#if defined(HAVE_FFMPEG)
    return @"FFmpeg is working on iOS";
#else
    return @"FFmpeg STUB mode - libraries not loaded";
#endif
}

- (NSNumber*)nativeCreateWithView:(UIView*)view {
    // Create FFmpeg player
    FFmpegPlayer* player = ffmpeg_player_create();
    if (!player) {
        NSLog(@"DashcamPlayer: Failed to create native player");
        return @(0);
    }

    // Create Metal renderer with the view
    MetalRenderer* renderer = metal_renderer_create((__bridge void*)view);
    if (!renderer) {
        NSLog(@"DashcamPlayer: Failed to create Metal renderer");
        ffmpeg_player_release(player);
        return @(0);
    }

    // Attach renderer to player
    ffmpeg_player_set_renderer(player, renderer);

    // Store renderer pointer for MTKView delegate access
    _rendererPtr = renderer;

    long long ptr = (long long)player;
    NSLog(@"DashcamPlayer: Native player created: ptr=%lld", ptr);
    return @(ptr);
}

- (void*)getRendererPointer {
    return _rendererPtr;
}

- (void)drawRenderer {
    if (_rendererPtr) {
        metal_renderer_draw((MetalRenderer*)_rendererPtr);
    }
}

- (BOOL)nativeConnect:(NSNumber*)playerPtr url:(NSString*)url {
    FFmpegPlayer* player = (FFmpegPlayer*)(long long)[playerPtr longLongValue];
    if (!player) return NO;

    const char* urlCStr = [url UTF8String];
    bool success = ffmpeg_player_connect(player, urlCStr);

    NSLog(@"DashcamPlayer: Connect to %@ → %@", url, success ? @"SUCCESS" : @"FAILED");
    return success ? YES : NO;
}

- (void)nativeStart:(NSNumber*)playerPtr {
    FFmpegPlayer* player = (FFmpegPlayer*)(long long)[playerPtr longLongValue];
    if (!player) return;

    ffmpeg_player_start(player);
    NSLog(@"DashcamPlayer: Playback started");
}

- (void)nativeStop:(NSNumber*)playerPtr {
    FFmpegPlayer* player = (FFmpegPlayer*)(long long)[playerPtr longLongValue];
    if (!player) return;

    ffmpeg_player_stop(player);
    NSLog(@"DashcamPlayer: Playback stopped");
}

- (void)nativeRelease:(NSNumber*)playerPtr {
    FFmpegPlayer* player = (FFmpegPlayer*)(long long)[playerPtr longLongValue];
    if (!player) return;

    ffmpeg_player_release(player);
    _rendererPtr = nullptr;
    NSLog(@"DashcamPlayer: Player released");
}

@end
