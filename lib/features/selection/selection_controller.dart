import 'package:flutter/foundation.dart';

import '../../core/models/transfer.dart';
import '../../core/services/file_picker_service.dart';

/// The files queued to send.
///
/// Holds paths and sizes only. Nothing here ever opens a file - that is the
/// transfer engine's job, and it streams.
class SelectionController extends ChangeNotifier {
  final List<TransferFile> _files = <TransferFile>[];

  /// True while a native picker is open, so the buttons can show they are busy
  /// and a second picker cannot be opened on top of the first.
  bool _picking = false;

  List<TransferFile> get files => List<TransferFile>.unmodifiable(_files);
  bool get isEmpty => _files.isEmpty;
  bool get isNotEmpty => _files.isNotEmpty;
  int get count => _files.length;
  bool get isPicking => _picking;

  int get totalBytes =>
      _files.fold<int>(0, (int sum, TransferFile f) => sum + f.size);

  Future<void> addFiles() => _pick(FilePickerService.pickFiles);

  Future<void> addFolder() => _pick(FilePickerService.pickFolder);

  /// Adds files dragged onto the window.
  Future<void> addPaths(List<String> paths) =>
      _pick(() => FilePickerService.fromPaths(paths));

  void remove(String id) {
    final int index = _files.indexWhere((TransferFile f) => f.id == id);
    if (index < 0) return;
    _files.removeAt(index);
    notifyListeners();
  }

  void clear() {
    if (_files.isEmpty) return;
    _files.clear();
    notifyListeners();
  }

  Future<void> _pick(Future<List<TransferFile>> Function() picker) async {
    if (_picking) return;
    _picking = true;
    notifyListeners();
    try {
      _merge(await picker());
    } finally {
      _picking = false;
      notifyListeners();
    }
  }

  /// Adds only files that are not already queued. Picking the same file twice
  /// should not send it twice.
  ///
  /// Keyed on the source rather than the name, because two folders can each
  /// hold a `report.pdf` and both are legitimately selectable.
  void _merge(List<TransferFile> incoming) {
    if (incoming.isEmpty) return;
    final Set<String> known = <String>{
      for (final TransferFile file in _files)
        if (file.source?.key case final String key) key,
    };
    for (final TransferFile file in incoming) {
      final String? key = file.source?.key;
      if (key == null || !known.add(key)) continue;
      _files.add(file);
    }
  }
}
