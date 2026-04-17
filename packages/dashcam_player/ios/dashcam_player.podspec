Pod::Spec.new do |s|
  s.name             = 'dashcam_player'
  s.version          = '0.1.0'
  s.summary          = 'Low-latency RTSP dashcam player using native FFmpeg'
  s.description      = <<-DESC
A Flutter plugin for delayless live streaming from F9 dashcam via RTSP,
using FFmpeg C++ with direct Metal surface rendering.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }

  # Source files: Swift, Obj-C++, C++, and our headers
  s.source_files     = 'Classes/**/*.{swift,h,m,mm,cpp}'
  # Only publish our own headers as public
  s.public_header_files = 'Classes/*.h', 'Classes/include/*.h'

  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # FFmpeg headers location (outside Classes/ to avoid duplicate header conflicts)
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/ffmpeg_headers"',
    # Enable FFmpeg usage
    'GCC_PREPROCESSOR_DEFINITIONS' => 'HAVE_FFMPEG=1',
    # C++ standard
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
  }

  s.swift_version = '5.0'

  # Frameworks for Metal rendering
  s.frameworks = 'Metal', 'MetalKit', 'AVFoundation', 'CoreVideo', 'Foundation'

  # Link FFmpeg libraries from media_kit_libs_ios_video
  s.dependency 'media_kit_libs_ios_video'
end
