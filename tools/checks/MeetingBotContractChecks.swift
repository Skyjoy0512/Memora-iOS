import Foundation

@main
struct MeetingBotContractChecks {
  static func main() {
    let target = checkTargets()
    checkLifecycle(target)
    print("MeetingBotContractChecks: passed (direct invitations, redaction, bounded approval, ordered scoped events, consent, disconnect, audio receipt; no provider/network)")
  }

  private static func checkTargets() -> MeetingBotTarget {
    let meet = MeetingBotTarget("HTTPS://Meet.Google.com:443/ABC-defg-HIJ?authuser=0")!
    precondition(meet.platform == .googleMeet && meet.joinURL.absoluteString == "https://meet.google.com/abc-defg-hij")
    let short = MeetingBotTarget("https://teams.microsoft.com/meet/123456789012?p=Synthetic7")!
    precondition(short.platform == .microsoftTeams && short.joinURL.absoluteString.hasSuffix("?p=Synthetic7"))
    let thread = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_c29tZS1pZA%40thread.v2/0"
    let context = "?context=%7b%22Tid%22%3a%2211111111-1111-4111-8111-111111111111%22%7d"
    let long = MeetingBotTarget(thread + context)!
    precondition(long.platform == .microsoftTeams && MeetingBotTarget(long.joinURL.absoluteString) == long)
    precondition(MeetingBotTarget(thread)?.platform == .microsoftTeams)

    for invalid in [
      "http://meet.google.com/abc-defg-hij",
      "https://meet.google.com.invalid/abc-defg-hij",
      "https://meet.google.com./abc-defg-hij",
      "https://meet.google.com:444/abc-defg-hij",
      "https://user@meet.google.com/abc-defg-hij",
      "https://meet.google.com/lookup/example",
      "https://meet.google.com/abc-defg-hij#ignored",
      "https://meet.google.com/abc-defg-hij/extra",
      "https://meet.google.com/abc-defg-hij\n",
      "https://meet.google.com/%61bc-defg-hij",
      "https://meet.google.com/abc--hij",
      "https://teams.microsoft.com/l/chat/0",
      "https://teams.microsoft.com/meet/12345",
      "https://teams.microsoft.com/meet/12345?p=Abc&p=Def",
      "https://teams.microsoft.com/meet/12345?p=Abc&homeCloud=other",
      "https://teams.microsoft.com/meet/12345?p=Abc%2Fdef",
      "https://teams.microsoft.com/meet/12345?p=" + String(repeating: "a", count: 4_096),
      "https://teams.microsoft.com/l/meetup-join/19%253ameeting_c29tZS1pZA%40thread.v2/0",
      thread + "?fqdn=other",
      thread + "?context=%7b%22Tid%22%3a%22bad%22%7d",
      thread + context + "&homeCloud=other",
    ] { precondition(MeetingBotTarget(invalid) == nil) }

    for rendering in [String(describing: meet), String(reflecting: short), String(reflecting: long)] {
      precondition(!rendering.contains("https:") && !rendering.contains("Synthetic7") && !rendering.contains("11111111"))
    }
    precondition(Mirror(reflecting: meet).children.map(\.label) == ["platform"])
    return meet
  }

  private static func checkLifecycle(_ target: MeetingBotTarget) {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let deadline = now.addingTimeInterval(300)
    let scope = MeetingBotJob.Scope(accountID: "test-account", workspaceID: "test-workspace")!
    let otherScope = MeetingBotJob.Scope(accountID: scope.accountID, workspaceID: "different-workspace")!
    precondition(MeetingBotJob.Scope(accountID: "", workspaceID: nil) == nil)
    precondition(MeetingBotJob.Scope(accountID: scope.accountID, workspaceID: "") == nil)
    precondition(MeetingBotJob.Scope(accountID: String(repeating: "a", count: 257), workspaceID: nil) == nil)
    precondition(MeetingBotJob.Scope(accountID: scope.accountID, workspaceID: String(repeating: "a", count: 257)) == nil)
    precondition(MeetingBotJob.Scope(accountID: scope.accountID, workspaceID: "invalid\nworkspace") == nil)
    let composed = MeetingBotJob.Scope(accountID: scope.accountID, workspaceID: "é")!
    let decomposed = MeetingBotJob.Scope(accountID: scope.accountID, workspaceID: "e\u{301}")!
    precondition(composed != decomposed)
    let request = MeetingBotJoinRequest(id: UUID(), target: target, scope: scope, projectID: UUID(),
      maximumRecordingSeconds: 3_600, maximumAudioBytes: 2_048, approvedAt: now, submitBefore: deadline)!
    precondition(request.isApproved(at: now) && !request.isApproved(at: deadline))
    precondition(!request.isApproved(at: now.addingTimeInterval(-1)))
    precondition(MeetingBotJoinRequest(id: request.id, target: target, scope: scope, projectID: nil,
      maximumRecordingSeconds: 0, maximumAudioBytes: 2_048, approvedAt: now, submitBefore: deadline) == nil)
    precondition(MeetingBotJoinRequest(id: request.id, target: target, scope: scope, projectID: nil,
      maximumRecordingSeconds: 3_600, maximumAudioBytes: 2_048, approvedAt: now, submitBefore: now) == nil)
    precondition(MeetingBotJoinRequest(id: request.id, target: target, scope: scope, projectID: nil,
      maximumRecordingSeconds: 3_600, maximumAudioBytes: 0, approvedAt: now, submitBefore: deadline) == nil)

    let jobID = UUID()
    precondition(MeetingBotJob(id: jobID, request: request, acceptedAt: deadline) == nil)
    var job = MeetingBotJob(id: jobID, request: request, acceptedAt: now)!
    precondition(job.requestID == request.id && job.scope == scope && job.projectID == request.projectID)
    func update(_ sequence: UInt64, _ event: MeetingBotJob.Update.Event) -> MeetingBotJob.Update {
      .init(jobID: jobID, scope: scope, sequence: sequence, event: event)
    }
    let recording = MeetingBotJob.Update.Event.recordingStarted(noticeConfirmedAt: now, consentVerifiedAt: now)
    precondition(!job.apply(update(1, recording)) && job.phase == .requested)
    precondition(!job.apply(.init(jobID: jobID, scope: otherScope, sequence: 1, event: .waitingForAdmission)))
    precondition(!job.apply(.init(jobID: UUID(), scope: scope, sequence: 1, event: .waitingForAdmission)))
    precondition(!job.apply(update(2, .admitted(now))) && job.lastSequence == 0)
    precondition(job.apply(update(1, .waitingForAdmission)))
    precondition(!job.apply(update(1, .waitingForAdmission)))
    precondition(!job.apply(update(2, .admitted(now.addingTimeInterval(-1)))))
    var denied = job
    precondition(denied.apply(update(2, .denied)) && denied.phase == .denied)
    precondition(!denied.apply(update(3, .admitted(now))))

    precondition(job.apply(update(2, .admitted(now))) && job.phase == .awaitingConsent(admittedAt: now))
    precondition(!job.apply(update(3, .recordingStarted(noticeConfirmedAt: now, consentVerifiedAt: now.addingTimeInterval(-1)))))
    precondition(job.apply(update(3, recording)) && job.phase == .recording)
    var disconnected = job
    precondition(disconnected.apply(update(4, .disconnected)) && disconnected.phase == .disconnected)
    precondition(!disconnected.apply(update(5, .finalizing)))
    precondition(job.apply(update(4, .finalizing)) && job.phase == .finalizing)

    let digest = String(repeating: "a", count: 64)
    let audioID = UUID()
    let audio = MeetingBotJob.Audio(id: audioID, format: .m4a, byteCount: 1024, duration: 600, sha256: digest)!
    let tooLong = MeetingBotJob.Audio(id: audioID, format: .m4a, byteCount: 1024, duration: 3_601, sha256: digest)!
    let tooLarge = MeetingBotJob.Audio(id: audioID, format: .m4a, byteCount: 2049, duration: 600, sha256: digest)!
    precondition(MeetingBotJob.Audio(id: audioID, format: .wav, byteCount: 1, duration: 1, sha256: "bad") == nil)
    precondition(!job.apply(update(5, .audioReady(tooLong))))
    precondition(!job.apply(update(5, .audioReady(tooLarge))))
    precondition(job.apply(update(5, .audioReady(audio))) && job.phase == .audioReady(audio))
    let recordID = UUID()
    var expired = job
    precondition(!expired.apply(update(6, .audioExpired(audioID: UUID()))))
    precondition(expired.apply(update(6, .audioExpired(audioID: audioID))) && expired.phase == .expired)
    precondition(!expired.apply(update(7, .imported(audioID: audioID, recordID: recordID))))
    precondition(!job.apply(update(6, .imported(audioID: UUID(), recordID: recordID))))
    precondition(job.apply(update(6, .imported(audioID: audioID, recordID: recordID))))
    precondition(!job.apply(update(6, .imported(audioID: audioID, recordID: recordID))) && job.phase == .imported(recordID: recordID))
  }
}
