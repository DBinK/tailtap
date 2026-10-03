import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var statusItem: NSStatusItem?
  private var trayChannel: FlutterMethodChannel?
  private weak var mainWindow: NSWindow?
  private var activeCount = 0
  private var taskSummary = ""
  private var keepRunningInMenuBar: Bool {
    get { UserDefaults.standard.object(forKey: "keepRunningInMenuBar") as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: "keepRunningInMenuBar") }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !keepRunningInMenuBar
  }

  func configureTray(messenger: FlutterBinaryMessenger, window: NSWindow) {
    mainWindow = window
    let channel = FlutterMethodChannel(name: "dev.tailtap/tray", binaryMessenger: messenger)
    trayChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "unavailable", message: "菜单栏不可用", details: nil)); return }
      if call.method == "getKeepRunning" {
        result(self.keepRunningInMenuBar)
        return
      }
      if call.method == "setKeepRunning", let value = call.arguments as? Bool {
        self.keepRunningInMenuBar = value
        result(nil)
        return
      }
      guard call.method == "setStatus", let values = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.activeCount = values["activeCount"] as? Int ?? 0
      self.taskSummary = values["summary"] as? String ?? ""
      self.updateTrayMenu()
      result(nil)
    }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "TailTap")
    item.button?.toolTip = "TailTap"
    statusItem = item
    updateTrayMenu()
  }

  private func updateTrayMenu() {
    guard let statusItem else { return }
    statusItem.button?.title = activeCount > 0 ? " \(activeCount)" : ""
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "打开 TailTap", action: #selector(showMainWindow), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: activeCount == 0 ? "没有运行中的任务" : "运行中：\(taskSummary)", action: nil, keyEquivalent: ""))
    menu.addItem(.separator())
    let stop = NSMenuItem(title: "停止全部任务", action: #selector(stopAllTasks), keyEquivalent: "")
    stop.isEnabled = activeCount > 0
    menu.addItem(stop)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "退出 TailTap", action: #selector(quitApp), keyEquivalent: "q"))
    for item in menu.items { item.target = self }
    statusItem.menu = menu
  }

  @objc private func showMainWindow() {
    guard let mainWindow else { return }
    mainWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func stopAllTasks() {
    trayChannel?.invokeMethod("stopAll", arguments: nil)
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
