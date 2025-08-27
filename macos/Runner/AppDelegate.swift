import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    if (filename as NSString).pathExtension.lowercased() == "daliproj" {
      if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(name: "org.tonycloud.dalimaster/import", binaryMessenger: controller.engine.binaryMessenger)
        if let data = try? Data(contentsOf: URL(fileURLWithPath: filename)), let json = String(data: data, encoding: .utf8) {
          channel.invokeMethod("importProjectJson", arguments: json)
          return true
        }
      }
    }
    return false
  }
}
