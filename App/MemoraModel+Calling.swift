import Foundation

// Calls placed from Memora, noted and transcribed like a meeting. The calling
// provider is reached only through `callingService`; until one is connected
// every step says so.
extension MemoraModel {
  /// The number verified as this person's caller ID, in E.164.
  var verifiedCallerNumber: String? {
    get { UserDefaults.standard.string(forKey: StorageKey.verifiedCallerNumber) }
    set { UserDefaults.standard.set(newValue, forKey: StorageKey.verifiedCallerNumber) }
  }

  /// Opens calling: the setup the first time, the dialer once a number is verified.
  func openCalling() {
    if verifiedCallerNumber == nil {
      isCallSetupPresented = true
    } else {
      isDialerPresented = true
    }
  }

  func placeCall(to number: String, contactName: String?) async throws -> PhoneCallSession {
    guard let callerID = verifiedCallerNumber else { throw CallingError.verificationFailed }
    guard let destination = PhoneNumberFormat.e164(number) else { throw CallingError.invalidNumber }
    let session = try await callingService.placeCall(to: destination, from: callerID)
    session.contactName = contactName
    activeCall = session
    return session
  }

  /// Keeps an ended call as a record, with its notes, and transcribes it on the
  /// device straight away, as a meeting recording is.
  func saveEndedCall(_ session: PhoneCallSession) {
    defer { activeCall = nil }
    guard let audio = session.recordingURL else { return }
    let duration = session.startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
    var meeting = Meeting(
      id: UUID(),
      title: session.title,
      createdAt: session.startedAt ?? .now,
      duration: max(duration, 1),
      source: .call,
      status: .waitingForTranscription,
      summary: "通話を保存しました。文字起こしを準備しています。",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: [],
      spaceID: nil,
      audioURL: audio
    )
    meeting.notes = session.notes
    meetings.insert(meeting, at: 0)
    persistMeetings()
    startTranscription(meeting.id)
  }
}
