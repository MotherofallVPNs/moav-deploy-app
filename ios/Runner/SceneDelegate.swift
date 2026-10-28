import Flutter
import UIKit

/// Covers the window as soon as the scene deactivates, before the iOS
/// snapshot; the Flutter shield underneath still owns the lock state.
class SceneDelegate: FlutterSceneDelegate {
  private var cover: UIView?

  override init() {
    super.init()
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(sceneWillDeactivate(_:)),
      name: UIScene.willDeactivateNotification, object: nil)
    center.addObserver(
      self, selector: #selector(sceneDidActivate(_:)),
      name: UIScene.didActivateNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func isOurScene(_ notification: Notification) -> Bool {
    guard let scene = notification.object as? UIScene else { return false }
    return scene === window?.windowScene
  }

  @objc private func sceneWillDeactivate(_ notification: Notification) {
    guard isOurScene(notification), cover == nil, let window = window else { return }
    let view = PrivacyCover.make(notes: DecoyChannel.coverIsNotes, bounds: window.bounds)
    window.addSubview(view)
    cover = view
  }

  @objc private func sceneDidActivate(_ notification: Notification) {
    guard isOurScene(notification) else { return }
    cover?.removeFromSuperview()
    cover = nil
  }
}

/// What the task switcher sees: the launch screen, or plain Notes paper
/// while disguised.
enum PrivacyCover {
  static func make(notes: Bool, bounds: CGRect) -> UIView {
    let view: UIView
    if notes {
      view = UIView(frame: bounds)
      view.backgroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
          ? UIColor(red: 0x1C / 255.0, green: 0x1B / 255.0, blue: 0x18 / 255.0, alpha: 1)
          : UIColor(red: 1, green: 0xFD / 255.0, blue: 0xF7 / 255.0, alpha: 1)
      }
    } else {
      let launch = UIStoryboard(name: "LaunchScreen", bundle: nil)
        .instantiateInitialViewController()?.view
      view = launch ?? UIView(frame: bounds)
      view.frame = bounds
    }
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.isUserInteractionEnabled = false
    return view
  }
}
