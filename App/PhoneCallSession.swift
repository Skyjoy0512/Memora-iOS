import Foundation
import Observation

/// One call placed from Memora: who, how long, and the controls on screen.
/// The calling provider drives it; the notes are the person's own and become
/// the record's notes when the call ends.
@MainActor
@Observable
final class PhoneCallSession: Identifiable {
  let id = UUID()
  var number: String
  var contactName: String?
  var startedAt: Date?
  var isMuted = false
  var isSpeakerOn = false
  /// Recording can be paused for part of a call, for example while consent is asked.
  var isRecording = true
  var notes = ""
  /// The recorded audio, once the call has ended.
  var recordingURL: URL?
  var hasEnded = false

  /// Hooks the provider sets, so the screen's buttons reach the real call.
  @ObservationIgnored var onHangUp: () -> Void = {}
  @ObservationIgnored var onMuteChange: (Bool) -> Void = { _ in }
  @ObservationIgnored var onSpeakerChange: (Bool) -> Void = { _ in }
  @ObservationIgnored var onRecordingChange: (Bool) -> Void = { _ in }
  @ObservationIgnored var onDigit: (String) -> Void = { _ in }

  init(number: String, contactName: String? = nil) {
    self.number = number
    self.contactName = contactName
  }

  var title: String {
    "\(contactName ?? PhoneNumberFormat.display(number))との通話"
  }
}
