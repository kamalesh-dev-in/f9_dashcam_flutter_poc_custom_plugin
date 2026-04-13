cmake_minimum_required(VERSION 3.10.2)
project("dashcamplayer")

# FFmpeg library directories
set(FFMPEG_DIR ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

# Include directories for our headers (including FFmpeg headers)
include_directories(${CMAKE_SOURCE_DIR}/include)

# Add FFmpeg include directories
if(EXISTS ${CMAKE_SOURCE_DIR}/include/libavcodec)
    # Headers are already in include directory
    message(STATUS "FFmpeg headers found in include directory")
endif()

# Check if FFmpeg libraries exist
set(FFMPEG_FOUND FALSE)
set(AVCODEC_LIB ${FFMPEG_DIR}/libavcodec.so)
set(AVFORMAT_LIB ${FFMPEG_DIR}/libavformat.so)
set(AVUTIL_LIB ${FFMPEG_DIR}/libavutil.so)
set(SWSCALE_LIB ${FFMPEG_DIR}/libswscale.so)

if(EXISTS ${AVCODEC_LIB} AND EXISTS ${AVFORMAT_LIB} AND EXISTS ${AVUTIL_LIB} AND EXISTS ${SWSCALE_LIB})
    set(FFMPEG_FOUND TRUE)
    message(STATUS "FFmpeg libraries found for ${ANDROID_ABI}")

    # Create imported targets for FFmpeg libraries
    add_library(avcodec SHARED IMPORTED)
    set_target_properties(avcodec PROPERTIES IMPORTED_LOCATION ${AVCODEC_LIB})

    add_library(avformat SHARED IMPORTED)
    set_target_properties(avformat PROPERTIES IMPORTED_LOCATION ${AVFORMAT_LIB})

    add_library(avutil SHARED IMPORTED)
    set_target_properties(avutil PROPERTIES IMPORTED_LOCATION ${AVUTIL_LIB})

    add_library(swscale SHARED IMPORTED)
    set_target_properties(swscale PROPERTIES IMPORTED_LOCATION ${SWSCALE_LIB})
else()
    message(STATUS "FFmpeg libraries NOT found for ${ANDROID_ABI} - building stub")
    message(STATUS "  Looking in: ${FFMPEG_DIR}")
endif()

# Add compile definition if FFmpeg is found
if(FFMPEG_FOUND)
    add_definitions(-DHAVE_FFMPEG)
    message(STATUS "Building with FFmpeg support")
else()
    message(STATUS "Building without FFmpeg support (stub mode)")
endif()

# Our native library
add_library(dashcamplayer SHARED
    src/jni_bridge.cpp
    src/ffmpeg_player.cpp
    src/surface_renderer.cpp)

# Link libraries (order matters - avutil first, then others)
if(FFMPEG_FOUND)
    target_link_libraries(dashcamplayer
        avutil
        swscale
        avcodec
        avformat
        android
        log)

    # Allow undefined symbols from shared libraries (FFmpeg has interdependencies)
    target_link_options(dashcamplayer PRIVATE -Wl,--allow-shlib-undefined)
    message(STATUS "Linking with FFmpeg libraries")
else()
    target_link_libraries(dashcamplayer
        android
        log)
    message(STATUS "Linking without FFmpeg libraries (stub mode)")
endif()
