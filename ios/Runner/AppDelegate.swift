import UIKit
import Flutter
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "org.tonycloud.dalimaster/import"
  private var methodChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    // Accept .daliproj files
    if url.pathExtension.lowercased() == "daliproj" {
      if let data = try? Data(contentsOf: url), let json = String(data: data, encoding: .utf8) {
        methodChannel?.invokeMethod("importProjectJson", arguments: json)
        return true
      }
    }
    return false
  }
}
