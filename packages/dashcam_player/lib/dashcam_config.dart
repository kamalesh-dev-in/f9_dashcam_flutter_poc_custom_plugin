/// Configuration for the dashcam player plugin.
///
/// All fields are optional. When not specified, F9 dashcam defaults are used.
/// Override any combination of network, endpoint, or RTSP settings for your dashcam.
///
/// ```dart
/// // F9 dashcam defaults (no config needed)
/// DashcamPlayerController()
///
/// // Custom dashcam — just change IP and ports
/// DashcamPlayerController(
///   config: DashcamConfig(ip: '192.168.0.100', rtspPort: 8554),
/// )
///
/// // Different dashcam brand — custom endpoints too
/// DashcamPlayerController(
///   config: DashcamConfig(
///     ip: '10.0.0.1',
///     heartbeatEndpoint: '/cgi-bin/ping',
///     enterRecorderEndpoint: '/cgi-bin/start_rec',
///     startLiveEndpoint: '/cgi-bin/live?cam=',
///     switchCameraEndpoint: '/cgi-bin/switch?ch=',
///   ),
/// )
/// ```
class DashcamConfig {
  // ── F9 Dashcam defaults ──────────────────────────────────────

  // Network
  static const String _defaultIp = '192.168.169.1';
  static const int _defaultRtspPort = 554;
  static const int _defaultHttpPort = 80;
  static const String _defaultUserAgent = 'HiCamera';

  // Endpoint paths (appended to http://ip:httpPort)
  static const String _defaultHeartbeatPath = '/app/getparamvalue?param=rec';
  static const String _defaultEnterRecorderPath = '/app/enterrecorder';
  static const String _defaultGetMediaInfoPath = '/app/getmediainfo';
  static const String _defaultStartLivePath = '/?custom=1&cmd=2015&par=';
  static const String _defaultSwitchCameraPath =
      '/app/setparamvalue?param=switchcam&value=';

  // ── Configurable fields (all optional) ───────────────────────

  /// Dashcam IP address. Default: `192.168.169.1`
  final String? ip;

  /// RTSP port. Default: `554`
  final int? rtspPort;

  /// HTTP port. Default: `80`
  final int? httpPort;

  /// User-Agent header for HTTP requests. Default: `HiCamera`
  final String? userAgent;

  /// Full heartbeat URL override.
  /// Default: `http://{ip}:{httpPort}/app/getparamvalue?param=rec`
  final String? heartbeatEndpoint;

  /// Full enter-recorder URL override.
  /// Default: `http://{ip}:{httpPort}/app/enterrecorder`
  final String? enterRecorderEndpoint;

  /// Full get-media-info URL override.
  /// Default: `http://{ip}:{httpPort}/app/getmediainfo`
  final String? getMediaInfoEndpoint;

  /// Full start-live-preview URL override. Camera index is appended.
  /// Default: `http://{ip}:{httpPort}/?custom=1&cmd=2015&par=`
  final String? startLiveEndpoint;

  /// Full switch-camera URL override. Camera index is appended.
  /// Default: `http://{ip}:{httpPort}/app/setparamvalue?param=switchcam&value=`
  final String? switchCameraEndpoint;

  /// Full RTSP URL override.
  /// Default: `rtsp://{ip}:{rtspPort}/`
  final String? rtspUrl;

  const DashcamConfig({
    this.ip,
    this.rtspPort,
    this.httpPort,
    this.userAgent,
    this.heartbeatEndpoint,
    this.enterRecorderEndpoint,
    this.getMediaInfoEndpoint,
    this.startLiveEndpoint,
    this.switchCameraEndpoint,
    this.rtspUrl,
  });

  // ── Effective values (override or F9 default) ────────────────

  String get effectiveIp => ip ?? _defaultIp;
  int get effectiveRtspPort => rtspPort ?? _defaultRtspPort;
  int get effectiveHttpPort => httpPort ?? _defaultHttpPort;
  String get effectiveUserAgent => userAgent ?? _defaultUserAgent;

  String get _httpBase => 'http://$effectiveIp:$effectiveHttpPort';

  /// Heartbeat URL
  String get effectiveHeartbeatEndpoint =>
      heartbeatEndpoint ?? '$_httpBase$_defaultHeartbeatPath';

  /// Enter recorder mode URL
  String get effectiveEnterRecorderEndpoint =>
      enterRecorderEndpoint ?? '$_httpBase$_defaultEnterRecorderPath';

  /// Get media info URL
  String get effectiveGetMediaInfoEndpoint =>
      getMediaInfoEndpoint ?? '$_httpBase$_defaultGetMediaInfoPath';

  /// Start live preview URL (camera index appended at runtime)
  String get effectiveStartLiveEndpoint =>
      startLiveEndpoint ?? '$_httpBase$_defaultStartLivePath';

  /// Switch camera URL (camera index appended at runtime)
  String get effectiveSwitchCameraEndpoint =>
      switchCameraEndpoint ?? '$_httpBase$_defaultSwitchCameraPath';

  /// RTSP URL
  String get effectiveRtspUrl =>
      rtspUrl ?? 'rtsp://$effectiveIp:$effectiveRtspPort/';

  /// Serialize only non-null values for passing to native side
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (ip != null) map['ip'] = ip;
    if (rtspPort != null) map['rtspPort'] = rtspPort;
    if (httpPort != null) map['httpPort'] = httpPort;
    if (userAgent != null) map['userAgent'] = userAgent;
    if (heartbeatEndpoint != null) map['heartbeatEndpoint'] = heartbeatEndpoint;
    if (enterRecorderEndpoint != null) map['enterRecorderEndpoint'] = enterRecorderEndpoint;
    if (getMediaInfoEndpoint != null) map['getMediaInfoEndpoint'] = getMediaInfoEndpoint;
    if (startLiveEndpoint != null) map['startLiveEndpoint'] = startLiveEndpoint;
    if (switchCameraEndpoint != null) map['switchCameraEndpoint'] = switchCameraEndpoint;
    if (rtspUrl != null) map['rtspUrl'] = rtspUrl;
    return map;
  }
}
