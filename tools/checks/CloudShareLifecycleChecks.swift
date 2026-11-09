import CloudKit
import Foundation

@main @MainActor
struct CloudShareLifecycleChecks {
  static func main() async throws {
    var record = Meeting(id: UUID(), title: "共有する会議", createdAt: .now, duration: 1,
      source: .recording, status: .ready, summary: "許可した本文", keyPoints: [], decisions: [],
      openQuestions: [], transcript: [], spaceID: nil, audioURL: nil)
    record.privacy = RecordPrivacy(classification: .general, allowsTeamSharing: true)
    let task = MemoraTask(id: UUID(), title: "共有する課題", meetingID: record.id, assignee: nil, dueDate: nil, isCompleted: false)
    func model() -> MemoraModel {
      let model = MemoraModel()
      model.meetings = [record]; model.tasks = [task]
      return model
    }
    for phase in ["availability", "zone", "write", "subscription"] {
      for change in 0..<9 {
        let model = model()
        let service = model.cloudSharing
        service.gate.phase = phase
        let operation = Task { await model.shareMeetingWithTeam(record.id) }
        await service.gate.entered()
        switch change {
        case 0:
          model.meetings[0].privacy.allowsTeamSharing = false
          model.meetings[0].privacy.allowsTeamSharing = true
        case 1: model.currentTeamID = "team"
        case 2: model.meetings[0].summary = "変更後の本文"
        case 3: model.tasks[0].title = "変更後の課題"
        case 4: model.hasTeamPlan = false
        case 5: model.isRestoring = true
        case 6: model.isStoreProtected = true
        case 7: operation.cancel()
        default: model.aiWorkspaceGeneration = UUID()
        }
        service.gate.resume()
        await operation.value
        precondition(model.pendingCloudShare == nil && model.cloudSharePreparation == nil && model.cloudShareTask == nil && !service.isWorking)
        precondition(service.privateDatabase.records.isEmpty)
        if phase == "write" || phase == "subscription" {
          precondition(service.privateDatabase.deleted.count == 2)
        } else { precondition(service.privateDatabase.savedPayloads.isEmpty) }
      }
    }
    let healthy = model()
    await healthy.shareMeetingWithTeam(record.id)
    precondition(healthy.pendingCloudShare != nil && healthy.cloudSharing.privateDatabase.records.count == 2)
    try await healthy.cloudSharing.discardUnpublishedShare(healthy.pendingCloudShare!)
    try await healthy.cloudSharing.discardUnpublishedShare(healthy.pendingCloudShare!)
    precondition(healthy.cloudSharing.privateDatabase.records.isEmpty)

    // An older account check cannot replace a newer prepared share.
    let replaced = model()
    replaced.cloudSharing.gate.phase = "availability"
    let oldOperation = Task { await replaced.shareMeetingWithTeam(record.id) }
    await replaced.cloudSharing.gate.entered()
    replaced.meetings[0].privacy.allowsTeamSharing = false
    replaced.meetings[0].privacy.allowsTeamSharing = true
    replaced.cloudSharing.gate.phase = nil
    await replaced.shareMeetingWithTeam(record.id)
    let replacementID = replaced.pendingCloudShare?.share.recordID
    precondition(replacementID != nil)
    replaced.cloudSharing.gate.resume()
    await oldOperation.value
    precondition(replaced.pendingCloudShare?.share.recordID == replacementID)
    precondition(replaced.cloudSharing.privateDatabase.savedPayloads.count == 1)

    // Reject a project whose content changes while availability is checked.
    let project = model()
    let space = MemoraSpace(id: UUID(), name: "共有案件", symbol: "folder")
    project.spaces = [space]
    project.meetings[0].spaceID = space.id
    project.cloudSharing.gate.phase = "availability"
    let projectOperation = Task { await project.shareSpaceWithTeam(space.id) }
    await project.cloudSharing.gate.entered()
    project.spaces[0].name = "変更した案件名"
    project.cloudSharing.gate.resume()
    await projectOperation.value
    precondition(project.pendingCloudShare == nil && project.cloudSharing.privateDatabase.savedPayloads.isEmpty)

    // The UI must report cleanup failure and still withhold the sharing sheet.
    let failedCleanup = model()
    failedCleanup.cloudSharing.gate.phase = "write"
    failedCleanup.cloudSharing.privateDatabase.rejectCleanup = true
    let failureOperation = Task { await failedCleanup.shareMeetingWithTeam(record.id) }
    await failedCleanup.cloudSharing.gate.entered()
    failedCleanup.meetings[0].privacy.allowsTeamSharing = false
    failedCleanup.cloudSharing.gate.resume()
    await failureOperation.value
    precondition(failedCleanup.pendingCloudShare == nil && failedCleanup.cloudShareMessage?.contains("一時データ") == true)
    precondition(failedCleanup.cloudSharing.privateDatabase.records.count == 2)
    print("PASS: production CloudKit preparation/save/cleanup methods; 36 suspended availability/zone/save/subscription races, OFF/ON, workspace/data/plan/restore/protected/cancel refusal, personal success and cleanup-failure reporting. CKRecord/CKShare are real; model/database/availability are fixtures, no iCloud requests.")
  }
}

@MainActor final class MemoraModel {
  var meetings: [Meeting] = [] { didSet { invalidatePendingCloudShare() } }
  var tasks: [MemoraTask] = [] { didSet { invalidatePendingCloudShare() } }
  var spaces: [MemoraSpace] = [] { didSet { invalidatePendingCloudShare() } }
  var hasTeamPlan = true { didSet { invalidatePendingCloudShare() } }
  var currentTeamID: String? { didSet { invalidatePendingCloudShare() } }
  var aiWorkspaceGeneration = UUID() { didSet { invalidatePendingCloudShare() } }
  var isRestoring = false { didSet { invalidatePendingCloudShare() } }
  var isStoreProtected = false { didSet { invalidatePendingCloudShare() } }
  var profile = ProfileFixture(name: "共有する人")
  var cloudSharing = CloudSharingService()
  var cloudSharePreparation: CloudSharePreparation?
  var cloudShareTask: (id: UUID, task: Task<CloudSharingService.ShareRequest, Error>)?
  var cloudShareMessage: String?
  var pendingCloudShare: CloudSharingService.ShareRequest?
  func meeting(id: UUID) -> Meeting? { meetings.first { $0.id == id } }
  func space(id: UUID) -> MemoraSpace? { spaces.first { $0.id == id } }
  func allowsRecordAccess(_ id: UUID, purpose: RecordAccessPolicy.Purpose) -> Bool {
    meeting(id: id).map { RecordAccessPolicy.allows($0.privacy, purpose: purpose) } ?? false
  }
  func allowsRecordAccess(_ target: RecordPrivacyTargetFixture, purpose: RecordAccessPolicy.Purpose) -> Bool { true }
  func allowsTaskAccess(_ task: MemoraTask, purpose: RecordAccessPolicy.Purpose) -> Bool {
    RecordAccessPolicy.allowsRelated(task.privacy, parentID: task.meetingID,
      parentPrivacy: task.meetingID.flatMap { meeting(id: $0)?.privacy }, purpose: purpose, inheritsParent: true)
  }
}
enum RecordPrivacyTargetFixture { case task(UUID) }
struct ProfileFixture { var name: String }
@MainActor final class CloudSharingService {
  struct ShareRequest { var share: CKShare; var container: String; var title: String; var rootRecordID: CKRecord.ID }
  static let zoneName = "FixtureZone", recordType = "FixtureRecord"
  var gate = CloudShareGate()
  lazy var privateDatabase = CloudDatabaseFixture(gate: gate)
  var container = "fixture"
  var isWorking = false
  var availabilityMessage: String?
  func refreshAvailability() async { await gate.wait(at: "availability") }
  func subscribeIfNeeded() async throws { await gate.wait(at: "subscription") }
}
@MainActor final class CloudDatabaseFixture {
  struct Outcome {
    var saveResults: [CKRecord.ID: Result<CKRecord, Error>]
    var deleteResults: [CKRecord.ID: Result<Void, Error>]
  }
  var gate: CloudShareGate
  var records: [CKRecord.ID: CKRecord] = [:]
  var deleted: Set<CKRecord.ID> = []
  var savedPayloads: [Data] = []
  var rejectCleanup = false
  init(gate: CloudShareGate) { self.gate = gate }
  func save(_ zone: CKRecordZone) async throws -> CKRecordZone { await gate.wait(at: "zone"); return zone }
  func modifyRecords(saving: [CKRecord], deleting: [CKRecord.ID], savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
                     atomically: Bool) async throws -> Outcome {
    if !deleting.isEmpty {
      precondition(!Task.isCancelled, "Cleanup inherited the cancelled preparation")
      if rejectCleanup { throw CloudSharingError.saveFailed }
      var results: [CKRecord.ID: Result<Void, Error>] = [:]
      for id in deleting {
        results[id] = records.removeValue(forKey: id) == nil ? .failure(CKError(.unknownItem)) : .success(())
        deleted.insert(id)
      }
      return .init(saveResults: [:], deleteResults: results)
    }
    for record in saving {
      records[record.recordID] = record
      if let payload = record["payload"] as? Data { savedPayloads.append(payload) }
    }
    await gate.wait(at: "write")
    return .init(saveResults: Dictionary(uniqueKeysWithValues: saving.map { ($0.recordID, .success($0)) }), deleteResults: [:])
  }
}
@MainActor final class CloudShareGate {
  var phase: String?
  var continuation: CheckedContinuation<Void, Never>?
  func wait(at phase: String) async {
    if self.phase == phase { await withCheckedContinuation { continuation = $0 } }
  }
  func entered() async {
    for _ in 0..<10000 { if continuation != nil { return }; await Task.yield() }
    preconditionFailure("Cloud fixture did not reach the gate")
  }
  func resume() { let waiting = continuation; continuation = nil; phase = nil; waiting?.resume() }
}
enum RecordStore { static func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) } }
enum MediaFiles {
  static func reference(for url: URL) -> String? { url.lastPathComponent }
  static func resolve(_ name: String) -> URL? { nil }
  static func writePhoto(_ data: Data) -> String? { nil }
  @discardableResult static func deletePhoto(_ name: String) -> Bool { false }
}
struct TemplateSummary: Hashable, Codable {}
enum SummaryPreviewCache { static func preview(for id: UUID, summary: String, build: (String) -> String) -> String { build(summary) } }
enum MarkdownBlockParser { static func hasBlockStructure(_ text: String) -> Bool { false }; static func overview(of text: String) -> String { text } }
