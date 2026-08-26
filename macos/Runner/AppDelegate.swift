import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Opening a file and showing it in Finder, done through NSWorkspace.
  ///
  /// `Process.run("open", ...)` is the obvious way and it does not work here:
  /// the App Sandbox blocks a sandboxed process from driving LaunchServices,
  /// so the command fails - quietly, which is worse. NSWorkspace goes through a
  /// system service the sandbox does permit, and it is the only supported route
  /// for a sandboxed app.
  ///
  /// The channel name matches the Android one, so the Dart side asks both
  /// platforms the same question.
  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController
      as? FlutterViewController else {
      super.applicationDidFinishLaunching(notification)
      return
    }

    FlutterMethodChannel(
      name: "hozasend/storage",
      binaryMessenger: controller.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      guard
        let arguments = call.arguments as? [String: Any],
        let target = arguments["target"] as? String
      else {
        result(false)
        return
      }
      let url = URL(fileURLWithPath: target)

      switch call.method {
      case "openFile":
        // False when nothing on this Mac handles the type, which the UI turns
        // into a word to the user rather than a silent no-op.
        result(NSWorkspace.shared.open(url))

      case "revealInFinder":
        // Opens the enclosing folder with the file already selected - better
        // than opening the folder alone, which is all Explorer can be trusted
        // to do on Windows.
        NSWorkspace.shared.activateFileViewerSelecting([url])
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(
      name: "hozasend/system_settings",
      binaryMessenger: controller.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "openWifi":
        result(AppDelegate.openFirst([
          // Ventura and later, then the pane name every earlier version used.
          "x-apple.systempreferences:com.apple.Network-Settings.extension",
          "x-apple.systempreferences:com.apple.preference.network",
        ]))

      case "openHotspot":
        // macOS calls it Internet Sharing, and it lives in Sharing rather than
        // in Network.
        result(AppDelegate.openFirst([
          "x-apple.systempreferences:com.apple.Sharing-Settings.extension",
          "x-apple.systempreferences:com.apple.preferences.sharing",
        ]))

      case "openFirewall":
        // Ventura moved the firewall out of Security & Privacy and into
        // Network; the older identifier is kept for everything before that.
        result(AppDelegate.openFirst([
          "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall",
          "x-apple.systempreferences:com.apple.preference.security?Firewall",
        ]))

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.applicationDidFinishLaunching(notification)
  }

  /// Opens the first of [candidates] this version of macOS recognises.
  ///
  /// Through NSWorkspace for the same reason opening a file is: a sandboxed
  /// process cannot drive LaunchServices with `open`, and the pane identifiers
  /// were renamed in Ventura, so more than one has to be tried.
  private static func openFirst(_ candidates: [String]) -> Bool {
    for candidate in candidates {
      guard let url = URL(string: candidate) else { continue }
      if NSWorkspace.shared.open(url) { return true }
    }
    return false
  }
}
