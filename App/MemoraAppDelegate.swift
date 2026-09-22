import CloudKit
import UIKit

/// Receives CloudKit shares opened from the system — a link in Messages or Mail,
/// say — so a teammate's invitation lands in the app.
final class MemoraAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
  ) {
    Task { @MainActor in
      await CloudSharingService.shared.accept(metadata)
    }
  }
}
