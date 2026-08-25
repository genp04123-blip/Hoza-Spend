import 'dart:convert';

import '../../core/models/transfer.dart';
import '../../core/utils/log.dart';
import 'preferences_service.dart';

/// Stores transfer history as a list of encoded JSON records.
///
/// Preferences rather than a database: the cap below keeps this to a few tens
/// of kilobytes, and the guide is explicit that HozaSend should not grow into a
/// file manager. A database would be a dependency and a migration story for
/// data the user mostly glances at.
class HistoryRepository {
  const HistoryRepository(this._prefs);

  /// Oldest entries fall off beyond this. Long enough to answer "where did that
  /// file go", short enough that it never becomes storage worth worrying about.
  static const int maxEntries = 100;

  static const String _tag = 'History';

  final PreferencesService _prefs;

  /// A record that fails to decode is skipped rather than taking the whole
  /// history with it - a half-written entry should cost one row, not all of it.
  List<TransferRecord> load() {
    final List<TransferRecord> records = <TransferRecord>[];
    for (final String entry in _prefs.history) {
      try {
        final Object? decoded = jsonDecode(entry);
        if (decoded is! Map<String, Object?>) continue;
        records.add(TransferRecord.fromJson(decoded));
      } catch (error) {
        Log.warn(_tag, 'Skipped an unreadable history entry: $error');
      }
    }
    return records;
  }

  Future<void> save(List<TransferRecord> records) {
    final List<TransferRecord> capped = records.length <= maxEntries
        ? records
        : records.sublist(0, maxEntries);
    return _prefs.setHistory(<String>[
      for (final TransferRecord record in capped) jsonEncode(record.toJson()),
    ]);
  }

  Future<void> clear() => _prefs.setHistory(const <String>[]);
}
