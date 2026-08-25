import 'package:flutter/foundation.dart';

import '../../core/models/transfer.dart';
import '../../data/local/history_repository.dart';

/// Everything this device has sent and received, newest first.
class HistoryController extends ChangeNotifier {
  HistoryController(this._repository);

  /// How many entries the home screen shows before "See all".
  static const int previewCount = 3;

  final HistoryRepository _repository;

  List<TransferRecord> _records = const <TransferRecord>[];

  List<TransferRecord> get records => _records;
  bool get isEmpty => _records.isEmpty;

  List<TransferRecord> get recent =>
      _records.take(previewCount).toList(growable: false);

  Future<void> load() async {
    _records = _sorted(_repository.load());
    notifyListeners();
  }

  /// Adds a finished transfer. Writing is not awaited by callers: history is a
  /// convenience, and a slow write must never hold up the success screen.
  Future<void> add(TransferRecord record) async {
    _records = _sorted(<TransferRecord>[record, ..._records]);
    notifyListeners();
    await _repository.save(_records);
  }

  Future<void> clear() async {
    if (_records.isEmpty) return;
    _records = const <TransferRecord>[];
    notifyListeners();
    await _repository.clear();
  }

  static List<TransferRecord> _sorted(List<TransferRecord> records) {
    final List<TransferRecord> copy = List<TransferRecord>.of(records)
      ..sort((TransferRecord a, TransferRecord b) =>
          b.startedAt.compareTo(a.startedAt));
    return List<TransferRecord>.unmodifiable(copy);
  }
}
