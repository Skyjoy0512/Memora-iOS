import CloudKit
import UIKit

/// Receives CloudKit shares opened from the system — a link in Messages or Mail,
/// say — so a teammate's invitation lands in the app.
final class MemoraAppDelegate: NSObject, UIApplicationDelegate {
  /// Starts the location logger outside the view tree, so a background relaunch
  /// still receives location events. It does nothing unless the setting is on.
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    AutoLocationLogger.shared.startIfEnabled()
    return true
  }

  func application(
    _ application: UIApplication,
    userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
  ) {
    Task { @MainActor in
      await CloudSharingService.shared.accept(metadata)
    }
  }
}
