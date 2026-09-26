import CloudKit
import UIKit
import UserNotifications

/// Receives CloudKit shares opened from the system — a link in Messages or Mail,
/// say — so a teammate's invitation lands in the app. Also receives taps on a
/// task reminder.
final class MemoraAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  /// Starts the location logger outside the view tree, so a background relaunch
  /// still receives location events. It does nothing unless the setting is on.
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
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

  /// A tapped reminder carries the task's id, so the app can open its editor.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let info = response.notification.request.content.userInfo
    guard let string = info[TaskReminderScheduler.taskIDKey] as? String,
          let id = UUID(uuidString: string) else { return }
    await MainActor.run {
      NotificationCenter.default.post(name: .taskReminderTapped, object: nil, userInfo: ["taskID": id])
    }
  }
}
