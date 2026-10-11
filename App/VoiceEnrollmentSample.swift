import Foundation

struct VoiceEnrollmentSample: Identifiable {
  var url: URL
  var duration: TimeInterval

  var id: String { url.lastPathComponent }
}
