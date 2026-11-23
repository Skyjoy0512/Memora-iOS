import Foundation
import UserNotifications

/// Points out usable copied content when the app returns to the foreground.
/// The notice never claims the copy, asks for notification permission or
/// reports pasteboard metadata and content.
enum PasteboardResumeNotice {
  static let notificationIdentifier = "memora.pasteboard.resume"

  @MainActor
  static func postIfNeeded() async {
    guard let reading = PasteboardIntake.peek() else { return }

    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized ||
      settings.authorizationStatus == .provisional else { return }
    guard PasteboardResumeAnnouncement.value != reading.changeCount else { return }

    let content = UNMutableNotificationContent()
    content.title = "Memora"
    content.body = "コピーした内容があります。Ask AIの添付から追加できます。"
    content.sound = nil
    content.badge = nil

    let request = UNNotificationRequest(identifier: notificationIdentifier,
      content: content, trigger: nil)
    do {
      try await center.add(request)
      PasteboardResumeAnnouncement.value = reading.changeCount
    } catch {
      return
    }
  }
}

private enum PasteboardResumeAnnouncement {
  @MainActor static var value: Int?
}
