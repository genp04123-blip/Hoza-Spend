import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/log.dart';

/// Files another app has handed to HozaSend.
///
/// Three ways in, all landing here: Android's share sheet, Windows' "Send to"
/// and "Open with", and a file dropped straight onto the exe. Whichever it is,
/// the app has to end up in the same place - the send screen, with those files
/// already queued - because the user has already said what they want to do.
///
/// The handover is deliberately two-way. The launching share is *pulled*: the
/// app asks for it once it is running, so nothing depends on a message
/// arriving before Dart was listening. A share that lands while the app is
/// already open is *pushed*, because there is nothing left to wait for.
class ShareIntake {
  ShareIntake._();

  static final ShareIntake instance = ShareIntake._();

  static const String _tag = 'Share';

  /// Matched in MainActivity.kt and in the Windows runner.
  static const MethodChannel _channel = MethodChannel('hozasend/share');

  final List<String> _pending = <String>[];

  void Function(List<String> paths)? _listener;

  bool _started = false;

  /// False until the app is past the splash. Files that arrive before then are
  /// held: pushing the send screen while the splash is still deciding where to
  /// open would put it under a route about to replace it.
  bool _ready = false;

  bool get hasPending => _pending.isNotEmpty;

  /// Called once, from `main`, with whatever the process was launched with.
  ///
  /// Never awaited. Android answers by copying the shared files out of the
  /// other app, and a share can be a two-gigabyte video: waiting for that
  /// before the first frame would hold the app on a blank window for as long
  /// as the copy takes. The files are queued when they arrive instead.
  ///
  /// [launchArguments] is the desktop half: Windows starts a fresh copy of the
  /// app with the file's path on the command line. Android has no such thing -
  /// the intent that started the activity is asked for instead.
  void start(List<String> launchArguments) {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler(_onNativeCall);
    _queue(_realPaths(launchArguments));
    unawaited(_pull());
  }

  /// Registers the one place that acts on shared files. Anything already
  /// waiting is delivered as soon as the app is ready for it.
  void listen(void Function(List<String> paths) onFiles) {
    _listener = onFiles;
    _flush();
  }

  void stopListening(void Function(List<String> paths) onFiles) {
    if (identical(_listener, onFiles)) _listener = null;
  }

  /// Told by the splash, once it has handed over to a real screen.
  void ready() {
    if (_ready) return;
    _ready = true;
    _flush();
  }

  /// Asks the native side for a share that arrived before Dart was listening -
  /// which is every share that started the app.
  Future<void> _pull() async {
    try {
      final List<Object?>? paths =
          await _channel.invokeMethod<List<Object?>>('consume');
      if (paths == null) return;
      _queue(paths.whereType<String>().toList());
    } on MissingPluginException {
      // A platform with no share intake of its own - Linux, and the phone
      // builds of macOS' cousin. Launch arguments still work there.
    } catch (error) {
      Log.warn(_tag, 'Could not read the shared files: $error');
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method != 'shared') return null;
    final List<Object?> arguments =
        (call.arguments as List<Object?>?) ?? const <Object?>[];
    _queue(arguments.whereType<String>().toList());
    return true;
  }

  void _queue(List<String> paths) {
    if (paths.isEmpty) return;
    Log.info(_tag, 'Received ${paths.length} shared item(s)');
    _pending.addAll(paths);
    _flush();
  }

  void _flush() {
    if (!_ready || _pending.isEmpty) return;
    final void Function(List<String> paths)? listener = _listener;
    if (listener == null) return;
    final List<String> paths = List<String>.of(_pending);
    _pending.clear();
    listener(paths);
  }

  /// Keeps the arguments that are actually files or folders.
  ///
  /// The command line also carries whatever the shell felt like adding, and
  /// `flutter run` adds switches of its own; anything that is not something on
  /// disk is not a share.
  List<String> _realPaths(List<String> arguments) {
    final List<String> paths = <String>[];
    for (final String argument in arguments) {
      if (argument.isEmpty || argument.startsWith('-')) continue;
      try {
        if (FileSystemEntity.typeSync(argument) ==
            FileSystemEntityType.notFound) {
          continue;
        }
      } catch (_) {
        continue;
      }
      paths.add(argument);
    }
    return paths;
  }
}
