#ifndef FFMPEG_PLAYER_H
#define FFMPEG_PLAYER_H

#include <stdbool.h>
#include <stdint.h>

// Forward declarations
typedef struct FFmpegPlayer FFmpegPlayer;
typedef struct MetalRenderer MetalRenderer;

// Create a new FFmpeg player instance
FFmpegPlayer* ffmpeg_player_create();

// Connect to an RTSP stream
bool ffmpeg_player_connect(FFmpegPlayer* player, const char* rtsp_url);

// Start playback (decoding + rendering)
void ffmpeg_player_start(FFmpegPlayer* player);

// Stop playback
void ffmpeg_player_stop(FFmpegPlayer* player);

// Set Metal renderer for video output
void ffmpeg_player_set_renderer(FFmpegPlayer* player, MetalRenderer* renderer);

// Release all resources
void ffmpeg_player_release(FFmpegPlayer* player);

#endif // FFMPEG_PLAYER_H
