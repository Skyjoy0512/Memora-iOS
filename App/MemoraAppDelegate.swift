import BackgroundTasks
import CloudKit
import UIKit
import UserNotifications

/// Receives CloudKit shares opened from the system — a link in Messages or Mail,
/// say — so a teammate's invitation lands in the app. Also receives taps on a
/// task reminder. It owns the model, so a background refresh that launches the
/// app without a window still has the records to work on.
@MainActor
final class MemoraAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  let model = MemoraModel()

  /// Starts the location logger outside the view tree, so a background relaunch
  /// still receives location events. It does nothing unless the setting is on.
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    AutoLocationLogger.shared.startIfEnabled()
    // Must be registered before launch finishes, or the system drops the task.
    BGTaskScheduler.shared.register(forTaskWithIdentifier: MemoraModel.residentRefreshTaskID, using: .main) { [model] task in
      guard let task = task as? BGAppRefreshTask else { return }
      MainActor.assumeIsolated { model.handleResidentRefresh(task) }
    }
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
    // A resident agent's notice opens the conversation it posted to.
    if info[MemoraModel.residentNotificationKey] != nil {
      await MainActor.run { model.selectedTab = .askAI }
      return
    }
    guard let string = info[TaskReminderScheduler.taskIDKey] as? String,
          let id = UUID(uuidString: string) else { return }
    await MainActor.run {
      NotificationCenter.default.post(name: .taskReminderTapped, object: nil, userInfo: ["taskID": id])
    }
  }
}
