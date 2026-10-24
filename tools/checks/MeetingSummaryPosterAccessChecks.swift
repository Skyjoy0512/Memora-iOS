import Foundation

// Boundary harness: the production snapshot is tested against explicit local
// state transitions. This does not claim UI or device permission validation.
@MainActor
final class MemoraModel {
  var currentTeamID: String?
  var aiWorkspaceGeneration = UUID()
  var isRestoring = false
  var isStoreProtected = false
  var record: FixtureRecord?
  enum Purpose { case onDeviceAI }
  func allowsRecordAccess(_ id: UUID, purpose: Purpose) -> Bool {
    !isRestoring && !isStoreProtected && record?.id == id
  }
  func meeting(id: UUID) -> FixtureRecord? { record?.id == id ? record : nil }
}

struct FixtureRecord {
  var id = UUID()
  var displayTitle = "検証用会議"
  var createdAt = Date(timeIntervalSince1970: 0)
  var summary = "保存済みの要約"
  var privacy = RecordPrivacy()
  var templateSensitivity = SummarySensitivity.general
  var effectivePrivacy: RecordPrivacy {
    var result = privacy
    result.protect(templateSensitivity)
    result.updatedAt = privacy.updatedAt
    return result
  }
}

@main
enum MeetingSummaryPosterAccessChecks {
  @MainActor
  static func main() {
    let model = MemoraModel()
    let record = FixtureRecord()
    model.record = record
    let snapshot = MeetingSummaryPosterSnapshot(meetingID: record.id, model: model)!
    let same = MeetingSummaryPosterSnapshot(meetingID: record.id, model: model)!
    precondition(snapshot.id != same.id && snapshot == same)
    precondition(snapshot.isCurrent(in: model))
    model.record?.summary = "変更後"
    precondition(snapshot != MeetingSummaryPosterSnapshot(meetingID: record.id, model: model))
    precondition(!snapshot.isCurrent(in: model))
    model.record = record
    model.record?.privacy.allowsCloudAI = true
    precondition(!snapshot.isCurrent(in: model))
    model.record = record
    model.record?.templateSensitivity = .sensitive
    precondition(!snapshot.isCurrent(in: model))
    model.record = record
    model.record?.displayTitle = "変更後"
    precondition(!snapshot.isCurrent(in: model))
    model.record = record
    model.record?.createdAt = .now
    precondition(!snapshot.isCurrent(in: model))
    model.record = nil
    precondition(!snapshot.isCurrent(in: model))
    model.record = record
    model.isRestoring = true
    precondition(!snapshot.isCurrent(in: model) && MeetingSummaryPosterSnapshot(meetingID: record.id, model: model) == nil)
    model.isRestoring = false
    model.isStoreProtected = true
    precondition(!snapshot.isCurrent(in: model))
    model.isStoreProtected = false
    model.currentTeamID = "team"
    precondition(!snapshot.isCurrent(in: model) && MeetingSummaryPosterSnapshot(meetingID: record.id, model: model) == nil)
    model.currentTeamID = nil
    model.aiWorkspaceGeneration = UUID()
    precondition(!snapshot.isCurrent(in: model))
    model.record?.summary = " \n"
    precondition(MeetingSummaryPosterSnapshot(meetingID: record.id, model: model) == nil)
    print("Poster access checks passed: edit, title, date, privacy, deletion, restore, protection, workspace A-B-A and empty source")
  }
}
