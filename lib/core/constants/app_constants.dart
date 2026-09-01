/// Product-wide constants. Anything two devices must agree on lives here.
class AppConstants {
  const AppConstants._();

  static const String appName = 'HozaSend';
  /// Must match `version:` in pubspec.yaml and AppVersion in
  /// installer/hoza_send.iss. It is what Settings, the home footer and the
  /// installer all display, and three different numbers for one build is how
  /// a bug report becomes unanswerable.
  static const String appVersion = '1.0.0';
  static const String tagline = 'Ready to share';

  static const String developerName = 'Rahoz Osman Salim';
  static const String developerEmail = 'hozahoza2001@gmail.com';

  /// Written out rather than taken from the clock: a copyright line marks when
  /// the work was published, not when someone happens to open the app.
  static const int copyrightYear = 2026;
  static const String copyright = '(c) $copyrightYear $developerName';

  /// Wire-format version. Bump when the beacon or transfer protocol changes in
  /// a way an older build cannot read; the handshake refuses a mismatch.
  ///
  /// 2: file bytes are carried in length-prefixed chunks rather than as one
  /// unbroken run of `size` bytes. Version 1 could not survive its own
  /// heartbeat - a pong written while a file was streaming landed inside the
  /// file - and had no safe moment to carry a cancel or a pause either.
  static const int protocolVersion = 2;

  /// UDP port for discovery beacons, broadcast across the local subnet.
  static const int discoveryPort = 47820;

  /// TCP port for the control channel and file streams.
  static const int transferPort = 47821;

  /// How many devices this one will hold a session with at the same time.
  ///
  /// Each session is a socket, a heartbeat and a receiver, so the ceiling is
  /// about keeping a phone tidy rather than about the protocol - nothing in
  /// the wire format cares how many peers there are. Three is about what a
  /// person can keep track of on one screen.
  static const int maxSessions = 3;

  /// Prefix on every beacon so unrelated UDP traffic on this port is ignored.
  static const String beaconMagic = 'HOZA1';

  /// How often this device announces itself while discovery is running.
  static const Duration beaconInterval = Duration(seconds: 2);

  /// A device drops off the list if no beacon arrives inside this window.
  static const Duration deviceTimeout = Duration(seconds: 7);

  /// Connection and handshake timeout.
  static const Duration connectionTimeout = Duration(seconds: 10);

  /// Bytes moved from disk to socket per chunk. Files are streamed; a file is
  /// never read into memory whole, however small it looks.
  ///
  /// It is also the frame size on the wire, and so the granularity at which a
  /// transfer can be paused or cancelled: the receiver returns to reading
  /// control lines after every chunk. Larger frames would shave an already
  /// negligible overhead (a ~30 byte header per 64 KB, under 0.05%) at the
  /// cost of making both of those coarser.
  static const int chunkSize = 64 * 1024;

  /// The most a peer may claim a single chunk holds.
  ///
  /// A frame header arrives over an open port, and the receiver allocates
  /// against it. Generous next to [chunkSize] so a future build may use larger
  /// frames, small enough that a hostile header cannot ask for a gigabyte.
  static const int maxChunkSize = 8 * 1024 * 1024;

  /// How often transfer progress is pushed to the UI. Throttled so a fast
  /// transfer cannot flood the widget tree with rebuilds.
  static const Duration progressInterval = Duration(milliseconds: 120);

  /// Suffix on a partially received file. It is renamed to the real name only
  /// once the byte count and the checksum both verify.
  static const String partialSuffix = '.hozapart';
}
