#ifndef DASHCAM_PLAYER_H
#define DASHCAM_PLAYER_H

#include <android/native_window_jni.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FFmpegPlayer FFmpegPlayer;

// Create FFmpeg player instance
FFmpegPlayer* ffmpeg_player_create();

// Connect to RTSP stream
bool ffmpeg_player_connect(FFmpegPlayer* player, const char* rtsp_url);

// Start playback
void ffmpeg_player_start(FFmpegPlayer* player);

// Stop playback
void ffmpeg_player_stop(FFmpegPlayer* player);

// Release player resources
void ffmpeg_player_release(FFmpegPlayer* player);

// Set surface for rendering
void ffmpeg_player_set_surface(FFmpegPlayer* player, JNIEnv* env, jobject surface);

#ifdef __cplusplus
}
#endif

#endif // DASHCAM_PLAYER_H
