import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    delegate = self
    (NSApp.delegate as? AppDelegate)?.configureTray(
      messenger: flutterViewController.engine.binaryMessenger,
      window: self
    )
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    let keepRunning = UserDefaults.standard.object(forKey: "keepRunningInMenuBar") as? Bool ?? true
    guard keepRunning else { return true }
    orderOut(nil)
    return false
  }
}
