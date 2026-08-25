import 'dart:convert';
import 'dart:math' as math;

/// Frames the byte stream on a HozaSession connection.
///
/// The connection carries two things: newline-terminated JSON control lines,
/// and raw file bytes. It switches between them - after a `file` header the
/// next [expectBinary] bytes are the file itself, then it returns to lines.
///
/// Lines are delivered through a callback rather than returned in a list,
/// because the handler for a `file` header has to be able to call
/// [expectBinary] *before* the next byte is interpreted. Returning a batch
/// would mean the file's own bytes had already been mis-parsed as lines.
///
/// It also puts a ceiling on how much it will buffer while looking for a
/// newline. This runs against an open TCP port; a peer that never sends one
/// must not be able to grow the buffer until the app dies.
class LineReader {
  static const int _newline = 0x0A;
  static const int _carriageReturn = 0x0D;

  /// A control line is a few hundred bytes. Anything near this is a bug or an
  /// attempt to exhaust memory.
  static const int maxLineBytes = 64 * 1024;

  final List<int> _buffer = <int>[];

  int _binaryRemaining = 0;
  void Function(List<int> bytes)? _onBytes;
  void Function()? _onBinaryDone;
  bool _overflowed = false;

  /// True once a single line exceeded [maxLineBytes]. The connection should be
  /// dropped; nothing sensible can follow.
  bool get hasOverflowed => _overflowed;

  bool get isReadingBinary => _binaryRemaining > 0;

  /// Routes the next [length] bytes to [onBytes] instead of parsing them as
  /// text, then calls [onDone] and returns to line mode.
  void expectBinary(
    int length, {
    required void Function(List<int> bytes) onBytes,
    required void Function() onDone,
  }) {
    if (length <= 0) {
      onDone();
      return;
    }
    _binaryRemaining = length;
    _onBytes = onBytes;
    _onBinaryDone = onDone;
  }

  void add(List<int> chunk, {required void Function(String line) onLine}) {
    if (_overflowed || chunk.isEmpty) return;

    // Fast path for the middle of a large file: no partial line pending and
    // the whole chunk belongs to the current file, so it goes straight to the
    // sink with no buffering or copying.
    if (_buffer.isEmpty && _binaryRemaining >= chunk.length) {
      _onBytes!(chunk);
      _binaryRemaining -= chunk.length;
      if (_binaryRemaining == 0) _finishBinary();
      return;
    }

    _buffer.addAll(chunk);
    _pump(onLine);
  }

  /// Bytes received that are not part of a complete line or the current file.
  List<int> takeRemaining() {
    final List<int> remaining = List<int>.of(_buffer);
    _buffer.clear();
    return remaining;
  }

  void _pump(void Function(String line) onLine) {
    while (_buffer.isNotEmpty) {
      if (_binaryRemaining > 0) {
        final int take = math.min(_binaryRemaining, _buffer.length);
        _onBytes!(_buffer.sublist(0, take));
        _buffer.removeRange(0, take);
        _binaryRemaining -= take;
        if (_binaryRemaining == 0) _finishBinary();
        continue;
      }

      final int end = _buffer.indexOf(_newline);
      if (end < 0) break;

      int stop = end;
      if (stop > 0 && _buffer[stop - 1] == _carriageReturn) stop--;
      final String line =
          utf8.decode(_buffer.sublist(0, stop), allowMalformed: true);
      _buffer.removeRange(0, end + 1);

      // Delivered one at a time so the handler can switch this reader into
      // binary mode before the loop looks at another byte.
      if (line.isNotEmpty) onLine(line);
    }

    if (_binaryRemaining == 0 && _buffer.length > maxLineBytes) {
      _overflowed = true;
      _buffer.clear();
    }
  }

  void _finishBinary() {
    final void Function()? done = _onBinaryDone;
    _onBytes = null;
    _onBinaryDone = null;
    done?.call();
  }
}
