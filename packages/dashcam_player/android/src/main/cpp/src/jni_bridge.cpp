#include <jni.h>
#include <android/log.h>
#include <string.h>
#include "ffmpeg_player.h"
#include "surface_renderer.h"

#define LOG_TAG "JNIBridge"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

// Helper to get player pointer from jlong
static FFmpegPlayer* getPlayer(jlong player_ptr) {
    return reinterpret_cast<FFmpegPlayer*>(player_ptr);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_dashcam_player_NativeFFmpegPlayer_nativeTest(
    JNIEnv* env,
    jobject /* this */) {

    LOGI("nativeTest called");
#if defined(HAVE_FFMPEG)
    return env->NewStringUTF("FFmpeg native library is working!");
#else
    return env->NewStringUTF("FFmpeg stub mode - add libraries to enable full functionality");
#endif
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_dashcam_player_NativeFFmpegPlayer_nativeCreate(
    JNIEnv* env,
    jobject /* this */,
    jobject surface) {

    LOGI("nativeCreate called");

    FFmpegPlayer* player = ffmpeg_player_create();
    if (!player) {
        LOGE("Failed to create FFmpegPlayer");
        return 0;
    }

    // Set surface if provided
    if (surface) {
        ffmpeg_player_set_surface(player, env, surface);
    }

    LOGI("FFmpegPlayer created successfully");
    return reinterpret_cast<jlong>(player);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_dashcam_player_NativeFFmpegPlayer_nativeConnect(
    JNIEnv* env,
    jobject /* this */,
    jlong player_ptr,
    jstring rtsp_url) {

    LOGI("nativeConnect called");

    FFmpegPlayer* player = getPlayer(player_ptr);
    if (!player) {
        LOGE("Invalid player pointer");
        return JNI_FALSE;
    }

    if (!rtsp_url) {
        LOGE("RTSP URL is null");
        return JNI_FALSE;
    }

    const char* url_str = env->GetStringUTFChars(rtsp_url, nullptr);
    if (!url_str) {
        LOGE("Failed to get RTSP URL string");
        return JNI_FALSE;
    }

    bool result = ffmpeg_player_connect(player, url_str);

    env->ReleaseStringUTFChars(rtsp_url, url_str);

    if (result) {
        LOGI("Connection successful");
        return JNI_TRUE;
    } else {
        LOGE("Connection failed");
        return JNI_FALSE;
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_dashcam_player_NativeFFmpegPlayer_nativeStart(
    JNIEnv* env,
    jobject /* this */,
    jlong player_ptr) {

    LOGI("nativeStart called");

    FFmpegPlayer* player = getPlayer(player_ptr);
    if (!player) {
        LOGE("Invalid player pointer");
        return;
    }

    ffmpeg_player_start(player);
}

extern "C" JNIEXPORT void JNICALL
Java_com_dashcam_player_NativeFFmpegPlayer_nativeStop(
    JNIEnv* env,
    jobject /* this */,
    jlong player_ptr) {

    LOGI("nativeStop called");

    FFmpegPlayer* player = getPlayer(player_ptr);
    if (!player) {
        LOGE("Invalid player pointer");
        return;
    }

    ffmpeg_player_stop(player);
}

extern "C" JNIEXPORT void JNICALL
Java_com_dashcam_player_NativeFFmpegPlayer_nativeRelease(
    JNIEnv* env,
    jobject /* this */,
    jlong player_ptr) {

    LOGI("nativeRelease called");

    FFmpegPlayer* player = getPlayer(player_ptr);
    if (!player) {
        LOGE("Invalid player pointer");
        return;
    }

    ffmpeg_player_release(player);
    LOGI("Player released");
}
