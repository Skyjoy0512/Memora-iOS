import AVFAudio
import CoreMedia
import Foundation

enum TranscriptionOutcome {
  case segments([TranscriptSegment])
  /// The engine ran and settled, but understood nothing: silence, or no speech
  /// in a language it can handle.
  case nothingRecognized
  /// No engine can run here — missing assets, an unsupported locale, or an
  /// engine that is not wired yet.
  case unavailable
  /// An engine ran but failed. `message` explains why and how to retry.
  case failed(String)
  /// The work was stopped before it produced anything. Nothing is applied and
  /// the audio is kept.
  case cancelled

  var diagnosticOutcome: AudioDiagnosticReport.Outcome {
    switch self {
    case .segments: .success
    case .nothingRecognized: .empty
    case .unavailable: .unavailable
    case .failed: .failed
    case .cancelled: .cancelled
    }
  }
}
