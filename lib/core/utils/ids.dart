/// Short unique ids for things that only need to be distinct within one run:
/// selected files, transfer sessions, queued items.
///
/// The device id is deliberately not generated here - that one has to survive
/// reinstalls and uses a cryptographic RNG in `DeviceIdentity`.
class Ids {
  const Ids._();

  static int _counter = 0;

  /// Timestamp plus a counter, both base36. The counter is what makes two ids
  /// minted in the same microsecond still differ.
  static String next([String prefix = '']) {
    final String stamp =
        DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$prefix$stamp${(_counter++).toRadixString(36)}';
  }
}
