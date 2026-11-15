import Foundation

enum LiveVoiceError: LocalizedError {
  case unavailable(String)

  var errorDescription: String? {
    switch self { case .unavailable(let reason): reason }
  }
}
