import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    DecoyChannel.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// Disguise mode on iOS: swaps the home screen icon for the "NotesIcon"
/// alternate icon. iOS cannot change the app's display name or launch
/// screen, so `capabilities` reports `renameLauncher: false` and the Dart
/// side explains the limitation to the user.
enum DecoyChannel {
  static let name = "org.motherofallvpns.moavdeploy/decoy"
  static let notesIcon = "NotesIcon"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let app = UIApplication.shared
      switch call.method {
      case "capabilities":
        result(["renameLauncher": false, "switchIcon": app.supportsAlternateIcons])
      case "getIdentity":
        result(app.alternateIconName == notesIcon ? "notes" : "moav")
      case "setIdentity":
        let args = call.arguments as? [String: Any]
        let notes = args?["notes"] as? Bool ?? false
        guard app.supportsAlternateIcons else {
          result(FlutterError(code: "unsupported", message: "Alternate icons unavailable", details: nil))
          return
        }
        let target: String? = notes ? notesIcon : nil
        if app.alternateIconName == target {
          result(true)
          return
        }
        app.setAlternateIconName(target) { error in
          if let error = error {
            result(FlutterError(code: "icon", message: error.localizedDescription, details: nil))
          } else {
            result(true)
          }
        }
      case "closeApp":
        // iOS apps must not terminate themselves; the icon updates in place.
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
