#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DashcamNativeBridge : NSObject

/// Test if FFmpeg is loaded and working
- (NSString*)nativeTest;

/// Create native player with a Metal view, returns player pointer as NSNumber
- (NSNumber*)nativeCreateWithView:(UIView*)view;

/// Get the MetalRenderer pointer from the last nativeCreate call (for MTKView delegate)
- (void* _Nullable)getRendererPointer;

/// Draw the current frame to screen (called by MTKView delegate on main thread)
- (void)drawRenderer;

/// Connect to RTSP stream
- (BOOL)nativeConnect:(NSNumber*)playerPtr url:(NSString*)url;

/// Start playback
- (void)nativeStart:(NSNumber*)playerPtr;

/// Stop playback
- (void)nativeStop:(NSNumber*)playerPtr;

/// Release all native resources
- (void)nativeRelease:(NSNumber*)playerPtr;

@end

NS_ASSUME_NONNULL_END
