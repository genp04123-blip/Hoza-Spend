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
  static const int protocolVersion = 1;

  /// UDP port for discovery beacons, broadcast across the local subnet.
  static const int discoveryPort = 47820;

  /// TCP port for the control channel and file streams.
  static const int transferPort = 47821;

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
  static const int chunkSize = 64 * 1024;

  /// How often transfer progress is pushed to the UI. Throttled so a fast
  /// transfer cannot flood the widget tree with rebuilds.
  static const Duration progressInterval = Duration(milliseconds: 120);

  /// Suffix on a partially received file. It is renamed to the real name only
  /// once the byte count and the checksum both verify.
  static const String partialSuffix = '.hozapart';
}
