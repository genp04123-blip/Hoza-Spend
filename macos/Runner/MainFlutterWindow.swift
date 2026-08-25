import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Matches the Windows runner: HozaSend is one column of cards, so extra
  /// height shows more devices while extra width only pads the margins.
  private static let initialSize = NSSize(width: 1120, height: 820)

  /// Below this the file cards and the send bar start fighting each other. The
  /// layout is responsive, not infinitely compressible.
  private static let minimumSize = NSSize(width: 680, height: 560)

  /// Byte for byte the colour the Dart splash opens on, and the same one
  /// Android's launch_background.xml uses. Without it the window paints the
  /// system default for a frame or two before Flutter's first frame lands,
  /// which reads as a flash on every launch - the macOS version of the white
  /// flash the Android template ships with.
  private static let launchColor = NSColor(
    srgbRed: 233.0 / 255.0,
    green: 245.0 / 255.0,
    blue: 254.0 / 255.0,
    alpha: 1
  )

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.backgroundColor = MainFlutterWindow.launchColor

    // Sized from the nib frame's origin so the window still opens where macOS
    // wanted it, then centred - a fixed origin would put it off-screen on a
    // second display.
    var windowFrame = self.frame
    windowFrame.size = MainFlutterWindow.initialSize
    self.setFrame(windowFrame, display: true)
    self.contentMinSize = MainFlutterWindow.minimumSize
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
