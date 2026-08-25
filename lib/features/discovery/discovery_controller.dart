import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/hoza_device.dart';
import '../../core/services/device_identity.dart';
import '../../core/services/wifi_lock_service.dart';
import '../../network/discovery/discovery_service.dart';
import '../../network/discovery/network_info.dart';
import '../settings/settings_controller.dart';

/// What the home screen shows about the network itself.
enum NetworkState {
  /// Interfaces have not been read yet. Only ever true for a moment.
  checking,

  /// No usable local network: no Wi-Fi, no hotspot, or no address yet.
  offline,

  /// On a local network. Says nothing about internet, which is irrelevant.
  ready,
}

/// The UI-facing half of discovery.
///
/// Owns a [DiscoveryService] and translates its stream into the handful of
/// things a screen actually needs: a device list, a network state, whether the
/// scanning animation should be running, and a message when something failed.
class DiscoveryController extends ChangeNotifier with WidgetsBindingObserver {
  DiscoveryController(this._settings) {
    _service = DiscoveryService(selfDevice: _selfDevice);
    _subscription = _service.stream.listen(_onDevices);
    WidgetsBinding.instance.addObserver(this);
  }

  /// How long the scanning animation runs before the screen settles into the
  /// empty state and offers Search again.
  ///
  /// A full minute, not a few seconds: the other device may still be starting
  /// up, joining the Wi-Fi, or having its hotspot switched on. Giving up after
  /// a moment tells the user "nothing is there" when the honest answer is
  /// "not yet". Discovery itself never stops - this only governs how long the
  /// radar keeps sweeping before the screen stops implying progress.
  static const Duration _searchWindow = Duration(seconds: 60);

  final SettingsController _settings;
  late final DiscoveryService _service;
  late final StreamSubscription<List<HozaDevice>> _subscription;
  Timer? _searchTimer;

  List<HozaDevice> _devices = const <HozaDevice>[];
  NetworkState _network = NetworkState.checking;
  bool _searching = false;
  String? _errorMessage;

  List<HozaDevice> get devices => _devices;
  NetworkState get network => _network;

  /// True while the radar should be sweeping: discovery is live, nothing has
  /// been found yet, and the search window has not elapsed.
  bool get isSearching =>
      _searching && _devices.isEmpty && _network == NetworkState.ready;

  /// Set when discovery could not start. Already phrased for a user.
  String? get errorMessage => _errorMessage;

  bool get isRunning => _service.isRunning;

  /// Begins advertising and listening. Safe to call when already running.
  Future<void> start() async {
    _errorMessage = null;
    if (_network != NetworkState.ready) {
      _network = NetworkState.checking;
      notifyListeners();
    }

    if (!await NetworkInfo.hasLocalNetwork()) {
      _network = NetworkState.offline;
      _searching = false;
      notifyListeners();
      return;
    }

    if (!await _service.start()) {
      _network = NetworkState.offline;
      _searching = false;
      _errorMessage =
          'HozaSend could not open the port it needs. Another app may be '
          'using it, or a firewall is blocking it.';
      notifyListeners();
      return;
    }

    // Held only while discovery is live, so the radio is not kept awake by an
    // idle app sitting in the background.
    unawaited(WifiLockService.acquire());

    _network = NetworkState.ready;
    _openSearchWindow();
    notifyListeners();
  }

  /// "Search again": clears the list, re-resolves the network and re-announces.
  /// Also recovers from the offline state, which is the common case after the
  /// user connects to Wi-Fi and comes back.
  Future<void> retry() async {
    if (!_service.isRunning) {
      await start();
      return;
    }
    _openSearchWindow();
    notifyListeners();
    await _service.refresh();
  }

  void stop() {
    _service.stop();
    unawaited(WifiLockService.release());
    _searchTimer?.cancel();
    _searching = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android freezes sockets in the background anyway. Stopping explicitly
    // saves battery and lets peers drop us straight away via the goodbye
    // beacon, rather than showing a device that is not really there.
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_service.isRunning) unawaited(start());
      case AppLifecycleState.paused:
        stop();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchTimer?.cancel();
    _subscription.cancel();
    _service.dispose();
    super.dispose();
  }

  void _onDevices(List<HozaDevice> devices) {
    _devices = devices;
    notifyListeners();
  }

  void _openSearchWindow() {
    _searching = true;
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchWindow, () {
      _searching = false;
      notifyListeners();
    });
  }

  /// The identity this device broadcasts. Read fresh on every beacon so a
  /// rename is picked up without restarting discovery.
  HozaDevice _selfDevice() => HozaDevice(
        id: _settings.deviceId,
        name: _settings.deviceName.isEmpty
            ? AppConstants.appName
            : _settings.deviceName,
        platform: DeviceIdentity.platform,
        // Filled in by the receiver from the packet's source address.
        address: '',
        port: AppConstants.transferPort,
        appVersion: AppConstants.appVersion,
        lastSeen: DateTime.now(),
      );
}
