#include "ffmpeg_player.h"
#include "surface_renderer.h"
#include <android/log.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/socket.h>
#include <arpa/inet.h>

#define LOG_TAG "FFmpegPlayer"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

// Check if FFmpeg is available
#if defined(HAVE_FFMPEG)
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}
#endif

// Playback thread function
static void* playback_thread(void* context);

// FFmpeg player structure
struct FFmpegPlayer {
    SurfaceRenderer* renderer;
    bool is_playing;
    bool is_connected;
    pthread_t playback_thread;
    pthread_mutex_t mutex;

    // RTSP URL (duplicated)
    char* rtsp_url;

#if defined(HAVE_FFMPEG)
    // FFmpeg contexts
    AVFormatContext* format_ctx;
    AVCodecContext* codec_ctx;
    int video_stream_index;
    SwsContext* sws_ctx;
#else
    // Stub data for building without FFmpeg
    void* stub_format_ctx;
#endif
};

// Create FFmpeg player
FFmpegPlayer* ffmpeg_player_create() {
    LOGI("Creating FFmpegPlayer");

    FFmpegPlayer* player = (FFmpegPlayer*)malloc(sizeof(FFmpegPlayer));
    if (!player) {
        LOGE("Failed to allocate FFmpegPlayer");
        return nullptr;
    }

    memset(player, 0, sizeof(FFmpegPlayer));
    player->renderer = surface_renderer_create();
    player->is_playing = false;
    player->is_connected = false;
    player->rtsp_url = nullptr;
    pthread_mutex_init(&player->mutex, nullptr);

#if defined(HAVE_FFMPEG)
    player->format_ctx = nullptr;
    player->codec_ctx = nullptr;
    player->video_stream_index = -1;
    player->sws_ctx = nullptr;

    // Initialize FFmpeg network (only once)
    static bool network_initialized = false;
    if (!network_initialized) {
        avformat_network_init();
        network_initialized = true;
        LOGI("FFmpeg network initialized");
    }
#else
    LOGI("Building without FFmpeg libraries - using stub implementation");
#endif

    return player;
}

// Connect to RTSP stream with IPv4-only enforcement
bool ffmpeg_player_connect(FFmpegPlayer* player, const char* rtsp_url) {
    if (!player || !rtsp_url) {
        LOGE("Invalid parameters for connect");
        return false;
    }

    LOGI("Connecting to: %s", rtsp_url);

#if defined(HAVE_FFMPEG)
    pthread_mutex_lock(&player->mutex);

    // Free previous connection resources (needed for camera switching)
    if (player->sws_ctx) {
        sws_freeContext(player->sws_ctx);
        player->sws_ctx = nullptr;
    }
    if (player->codec_ctx) {
        avcodec_free_context(&player->codec_ctx);
        player->codec_ctx = nullptr;
    }
    if (player->format_ctx) {
        avformat_close_input(&player->format_ctx);
        player->format_ctx = nullptr;
    }

    // Free previous URL if exists
    if (player->rtsp_url) {
        free(player->rtsp_url);
    }
    player->rtsp_url = strdup(rtsp_url);

    // Allocate format context
    player->format_ctx = avformat_alloc_context();
    if (!player->format_ctx) {
        LOGE("Failed to allocate format context");
        pthread_mutex_unlock(&player->mutex);
        return false;
    }

    // Use TCP transport with codec error handling (F9 dashcam has codec issues)
    AVDictionary* options = nullptr;
    av_dict_set(&options, "rtsp_transport", "tcp", 0);
    // Handle F9 dashcam's problematic stream format
    av_dict_set(&options, "err_detect", "ignore_err", 0);  // Ignore codec errors
    av_dict_set(&options, "fflags", "+genpts+igndts", 0);   // Generate PTS, ignore DTS
    av_dict_set(&options, "flags", "low_delay", 0);         // Low delay mode

    // Log connection attempt details
    LOGI("RTSP Connection Details:");
    LOGI("  URL: %s", rtsp_url);
    LOGI("  Transport: tcp");
    LOGI("  Options: codec error handling enabled");

    // Open RTSP stream
    LOGI("Opening RTSP stream with FFmpeg...");
    int ret = avformat_open_input(&player->format_ctx, rtsp_url, nullptr, &options);

    if (ret != 0) {
        char error_buf[128];
        av_strerror(ret, error_buf, sizeof(error_buf));
        LOGE("Failed to open RTSP stream: %s (error code: %d)", error_buf, ret);
        if (player->format_ctx) {
            avformat_close_input(&player->format_ctx);
            player->format_ctx = nullptr;
        }
        pthread_mutex_unlock(&player->mutex);
        return false;
    }

    // Free options
    av_dict_free(&options);

    // Get stream information
    LOGI("Getting stream information...");
    ret = avformat_find_stream_info(player->format_ctx, nullptr);
    if (ret < 0) {
        char error_buf[128];
        av_strerror(ret, error_buf, sizeof(error_buf));
        LOGE("Failed to get stream info: %s", error_buf);
        avformat_close_input(&player->format_ctx);
        player->format_ctx = nullptr;
        pthread_mutex_unlock(&player->mutex);
        return false;
    }

    // Find video stream
    player->video_stream_index = -1;
    for (unsigned int i = 0; i < player->format_ctx->nb_streams; i++) {
        if (player->format_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            player->video_stream_index = i;
            break;
        }
    }

    if (player->video_stream_index == -1) {
        LOGE("No video stream found");
        avformat_close_input(&player->format_ctx);
        player->format_ctx = nullptr;
        pthread_mutex_unlock(&player->mutex);
        return false;
    }

    LOGI("Found video stream at index %d", player->video_stream_index);

    // Get codec parameters
    AVCodecParameters* codec_par = player->format_ctx->streams[player->video_stream_index]->codecpar;
    const AVCodec* codec = avcodec_find_decoder(codec_par->codec_id);
    if (!codec) {
        LOGE("Unsupported codec");
        avformat_close_input(&player->format_ctx);
        player->format_ctx = nullptr;
        pthread_mutex_unlock(&player->mutex);
        return false;
    }

    // Allocate codec context
    player->codec_ctx = avcodec_alloc_context3(codec);
    if (!player->codec_ctx) {
        LOGE("Failed to allocate codec context");
        avformat_close_input(&player->format_ctx);
        player->format_ctx = nullptr;
        pthread_mutex_unlock(&player->mutex);
        return false;
    }

    // Copy codec parameters to codec context
    ret = avcodec_parameters_to_context(player->codec_ctx, codec_par);
    if (ret < 0) {
        char error_buf[128];
        av_strerror(ret, error_buf, sizeof(error_buf));
        LOGE("Failed to copy codec parameters: %s", error_buf);
        avcodec_free_context(&player->codec_ctx);
        player->codec_ctx = nullptr;
        avformat_close_input(&player->format_ctx);
        player->format_ctx = nullptr;
        pthread_mutex_unlock(&player->mutex);
        return false;
    }

    // Open codec
    ret = avcodec_open2(player->codec_ctx, codec, nullptr);
    if (ret < 0) {
        char error_buf[128];
        av_strerror(ret, error_buf, sizeof(error_buf));
        LOGE("Failed to open codec: %s", error_buf);
        avcodec_free_context(&player->codec_ctx);
        player->codec_ctx = nullptr;
        avformat_close_input(&player->format_ctx);
        player->format_ctx = nullptr;
        pthread_mutex_unlock(&player->mutex);
        return false;
    }

    LOGI("Codec opened successfully: %s", codec->name);
    LOGI("Video: %dx%d, format: %d",
         player->codec_ctx->width, player->codec_ctx->height,
         player->codec_ctx->pix_fmt);

    player->is_connected = true;
    pthread_mutex_unlock(&player->mutex);
    return true;

#else
    // Stub implementation - log connection attempt
    LOGI("STUB: Would connect to RTSP: %s", rtsp_url);
    LOGI("STUB: Add FFmpeg libraries to enable real functionality");

    // Store URL
    if (player->rtsp_url) {
        free(player->rtsp_url);
    }
    player->rtsp_url = strdup(rtsp_url);
    player->is_connected = true;

    return true;
#endif
}

// Playback thread function
static void* playback_thread(void* context) {
    FFmpegPlayer* player = (FFmpegPlayer*)context;

#if defined(HAVE_FFMPEG)
    LOGI("Playback thread started");

    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();

    if (!packet || !frame) {
        LOGE("Failed to allocate packet/frame");
        if (packet) av_packet_free(&packet);
        if (frame) av_frame_free(&frame);
        return nullptr;
    }

    while (player->is_playing && player->format_ctx) {
        pthread_mutex_lock(&player->mutex);

        // Read frame
        int ret = av_read_frame(player->format_ctx, packet);
        if (ret < 0) {
            if (ret == AVERROR_EOF) {
                LOGI("End of stream");
            } else {
                char error_buf[128];
                av_strerror(ret, error_buf, sizeof(error_buf));
                LOGE("Error reading frame: %s", error_buf);
            }
            pthread_mutex_unlock(&player->mutex);
            break;
        }

        // Check if this is a video packet
        if (packet->stream_index == player->video_stream_index) {
            // Send packet to decoder
            ret = avcodec_send_packet(player->codec_ctx, packet);
            if (ret < 0) {
                char error_buf[128];
                av_strerror(ret, error_buf, sizeof(error_buf));
                LOGE("Error sending packet to decoder: %s", error_buf);
                av_packet_unref(packet);
                pthread_mutex_unlock(&player->mutex);
                continue;
            }

            // Receive decoded frame
            while (ret >= 0) {
                ret = avcodec_receive_frame(player->codec_ctx, frame);
                if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
                    break;
                } else if (ret < 0) {
                    char error_buf[128];
                    av_strerror(ret, error_buf, sizeof(error_buf));
                    LOGE("Error decoding frame: %s", error_buf);
                    break;
                }

                LOGD("Decoded frame: %dx%d, format: %d",
                     frame->width, frame->height, frame->format);

                // Render frame to surface via SurfaceRenderer
                if (player->renderer) {
                    surface_renderer_render_frame(player->renderer, frame);
                }
            }
        }

        av_packet_unref(packet);
        pthread_mutex_unlock(&player->mutex);

        // Small sleep to prevent tight loop
        usleep(10000);  // 10ms
    }

    // Cleanup
    av_frame_free(&frame);
    av_packet_free(&packet);

    LOGI("Playback thread ended");
#else
    LOGI("STUB: Playback thread running (no FFmpeg)");
    while (player->is_playing) {
        usleep(100000);  // 100ms
    }
    LOGI("STUB: Playback thread ended");
#endif

    return nullptr;
}

// Start playback
void ffmpeg_player_start(FFmpegPlayer* player) {
    if (!player) {
        LOGE("Invalid player for start");
        return;
    }

    LOGI("Starting playback");

    if (!player->is_connected) {
        LOGE("Not connected, cannot start playback");
        return;
    }

    if (player->is_playing) {
        LOGI("Already playing");
        return;
    }

    player->is_playing = true;

    // Start playback thread
    if (pthread_create(&player->playback_thread, nullptr, playback_thread, player) != 0) {
        LOGE("Failed to create playback thread");
        player->is_playing = false;
        return;
    }

    LOGI("Playback started");
}

// Stop playback
void ffmpeg_player_stop(FFmpegPlayer* player) {
    if (!player) {
        LOGE("Invalid player for stop");
        return;
    }

    LOGI("Stopping playback");

    player->is_playing = false;

    // Wait for playback thread to end
    if (player->playback_thread) {
        pthread_join(player->playback_thread, nullptr);
        player->playback_thread = 0;
    }

    LOGI("Playback stopped");
}

// Set surface for rendering
void ffmpeg_player_set_surface(FFmpegPlayer* player, JNIEnv* env, jobject surface) {
    if (!player) {
        LOGE("Invalid player for set_surface");
        return;
    }

    LOGI("Setting surface");

    if (player->renderer) {
        surface_renderer_set_surface(player->renderer, env, surface);
    }
}

// Release resources
void ffmpeg_player_release(FFmpegPlayer* player) {
    if (!player) {
        return;
    }

    LOGI("Releasing FFmpegPlayer");

    // Stop playback if running
    if (player->is_playing) {
        ffmpeg_player_stop(player);
    }

    pthread_mutex_lock(&player->mutex);

#if defined(HAVE_FFMPEG)
    // Free FFmpeg resources
    if (player->sws_ctx) {
        sws_freeContext(player->sws_ctx);
        player->sws_ctx = nullptr;
    }

    if (player->codec_ctx) {
        avcodec_free_context(&player->codec_ctx);
        player->codec_ctx = nullptr;
    }

    if (player->format_ctx) {
        avformat_close_input(&player->format_ctx);
        player->format_ctx = nullptr;
    }
#endif

    // Free URL
    if (player->rtsp_url) {
        free(player->rtsp_url);
        player->rtsp_url = nullptr;
    }

    pthread_mutex_unlock(&player->mutex);

    // Release renderer
    if (player->renderer) {
        surface_renderer_release(player->renderer);
        player->renderer = nullptr;
    }

    // Destroy mutex
    pthread_mutex_destroy(&player->mutex);

    // Free player
    free(player);

    LOGI("FFmpegPlayer released");
}
