import Foundation

enum HealthReviewError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    "この端末ではヘルスケアの読み取りを利用できません。実際のiPhoneで確認してください。"
  }
}
