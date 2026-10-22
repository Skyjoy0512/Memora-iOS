import Foundation

enum AudioInbox {
  static var directory: URL {
    #if MEMORA_HOST_CHECKS
    guard let path = ProcessInfo.processInfo.environment["MEMORA_AUDIO_INBOX_DIRECTORY"], path.hasPrefix("/") else {
      preconditionFailure("Host audio Inbox directory is required")
    }
    return URL(fileURLWithPath: path, isDirectory: true)
    #else
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Inbox", isDirectory: true)
    #endif
  }
}
