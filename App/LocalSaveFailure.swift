import Foundation

enum LocalSaveFailure {
  static let notification = Notification.Name("memoraLocalSaveDidFail")

  @MainActor static func report(_ message: String) {
    NotificationCenter.default.post(name: notification, object: nil, userInfo: ["message": message])
  }
}
