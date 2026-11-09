import Foundation

enum TeamSharePackageChecks {
  @MainActor static func run() async throws {
    let model = TeamShareModelFixture()
    let person = Person(id: UUID(), name: "共有対象外の人物", note: "private note",
      contactIdentifier: "private contact", photoData: Data("private photo".utf8))
    var meeting = Meeting(id: UUID(), title: "共有する会議", createdAt: .now, duration: 1,
      source: .recording, status: .ready, summary: "許可した本文", keyPoints: [], decisions: [],
      openQuestions: [], transcript: [], spaceID: nil, audioURL: nil)
    meeting.privacy = RecordPrivacy(classification: .general)
    meeting.privacy.allowsTeamSharing = true
    meeting.participantIDs = [person.id]
    meeting.legacyPhotoData = [Data("old photo".utf8)]
    model.meetings = [meeting]
    model.people = [person]
    model.tasks = [.init(meetingID: meeting.id)]
    model.lifeLogEntries = [.init(meetingID: meeting.id, latitude: 35, longitude: 139,
      locationName: "private location", personIDs: [person.id])]
    MediaFiles.permitsFixturePhotoWrite = true
    defer {
      MediaFiles.permitsFixturePhotoWrite = false
      for name in model.meetings.flatMap({ $0.photoFileNames ?? [] }) {
        try? FileManager.default.removeItem(at: MediaFiles.photosDirectory.appendingPathComponent(name))
      }
    }
    let url = try await model.makeTeamSharePackage(meetingIDs: [meeting.id])
    defer { try? FileManager.default.removeItem(at: url) }
    let manifest = try BackupPackage.read(from: url)
    precondition(manifest.people.isEmpty && manifest.meetings[0].participantIDs == nil)
    precondition(manifest.tasks.count == 1 && manifest.aiHistory.isEmpty)
    precondition(manifest.lifeLogEntries[0].personIDs.isEmpty)
    precondition(manifest.lifeLogEntries[0].latitude == nil && manifest.lifeLogEntries[0].longitude == nil)
    precondition(manifest.lifeLogEntries[0].locationName == nil)
    precondition(manifest.meetings[0].legacyPhotoData == nil && manifest.photoFileNames.count == 1)
    let photo = url.appendingPathComponent(BackupPackage.mediaFolderName).appendingPathComponent(manifest.photoFileNames[0])
    let photoBytes = try Data(contentsOf: photo)
    precondition(photoBytes == Data("old photo".utf8))
    let json = try String(contentsOf: url.appendingPathComponent(BackupPackage.manifestName), encoding: .utf8)
    precondition(!json.contains("private note") && !json.contains("private contact"))
    precondition(model.people == [person] && model.meetings[0].participantIDs == [person.id])

    // The original package exists while each change happens on the main actor.
    for change in 0..<9 {
      let baseline = model.meetings
      let taskBaseline = model.tasks
      await TeamSharePackageGate.shared.arm()
      let operation = Task { try await model.makeTeamSharePackage(meetingIDs: [meeting.id]) }
      let pending = await TeamSharePackageGate.shared.entered()
      precondition(FileManager.default.fileExists(atPath: pending.path))
      switch change {
      case 0: model.meetings[0].privacy.allowsTeamSharing = false
      case 1: model.aiWorkspaceGeneration = UUID()
      case 2: model.meetings[0].summary = "書き出し後に編集"
      case 3: model.tasks[0].title = "書き出し後に編集"
      case 4: operation.cancel()
      case 5: model.hasTeamPlan = false
      case 6: model.deniedTaskIDs = Set(model.tasks.map(\.id))
      case 7: model.deniedJournalIDs = Set(model.lifeLogEntries.map(\.id))
      default: model.currentTeamID = UUID()
      }
      await TeamSharePackageGate.shared.resume()
      do {
        _ = try await operation.value
        preconditionFailure("Stale share escaped")
      } catch TeamShareError.privacyRestricted {}
      precondition(!FileManager.default.fileExists(atPath: pending.path))
      model.meetings = baseline
      model.tasks = taskBaseline
      model.hasTeamPlan = true
      model.deniedTaskIDs = []
      model.deniedJournalIDs = []
      model.currentTeamID = nil
    }
    do {
      _ = try await model.makeTeamSharePackage(meetingIDs: [meeting.id, UUID()])
      preconditionFailure("Missing record produced partial share")
    } catch TeamShareError.privacyRestricted {}
    print("PASS: production team package builder and real package files/Person codec; private person fields and location excluded, migrated photo included, stale permission/workspace/content/plan/cancelled exports removed. Related-record permission providers and write suspension are fixtures; no CloudKit/network.")
  }
}

@MainActor final class TeamShareModelFixture {
  var hasTeamPlan = true
  var aiWorkspaceGeneration = UUID()
  var currentTeamID: UUID?
  var meetings: [Meeting] = []
  var spaces: [MemoraSpace] = []
  var tasks: [MemoraTask] = []
  var lifeLogEntries: [LifeLogEntry] = []
  var people: [Person] = []
  var deniedTaskIDs: Set<UUID> = []
  var deniedJournalIDs: Set<UUID> = []
  func allowsRecordAccess(_ id: UUID, purpose: RecordAccessPolicy.Purpose) -> Bool {
    meetings.first { $0.id == id }.map { RecordAccessPolicy.allows($0.privacy, purpose: purpose) } ?? false
  }
  func allowsTaskAccess(_ task: MemoraTask, purpose: RecordAccessPolicy.Purpose) -> Bool { !deniedTaskIDs.contains(task.id) }
  func allowsJournalAccess(_ entry: LifeLogEntry, purpose: RecordAccessPolicy.Purpose) -> Bool { !deniedJournalIDs.contains(entry.id) }
}

enum TeamSharePackageWriter {
  static func write(meetings: [Meeting], spaces: [MemoraSpace], tasks: [MemoraTask],
                    lifeLogEntries: [LifeLogEntry], people: [Person], aiHistory: [AIConversationEntry], into directory: URL) async throws -> URL {
    let package = try BackupPackage.write(meetings: meetings, spaces: spaces, tasks: tasks,
      lifeLogEntries: lifeLogEntries, people: people, aiHistory: aiHistory, into: directory)
    await TeamSharePackageGate.shared.afterWrite(package)
    return package
  }
}

actor TeamSharePackageGate {
  static let shared = TeamSharePackageGate()
  var isArmed = false
  var package: URL?
  var continuation: CheckedContinuation<Void, Never>?
  func arm() { isArmed = true; package = nil }
  func afterWrite(_ url: URL) async {
    guard isArmed else { return }
    package = url
    await withCheckedContinuation { continuation = $0 }
  }
  func entered() async -> URL {
    while continuation == nil { await Task.yield() }
    return package!
  }
  func resume() {
    isArmed = false
    let waiting = continuation
    continuation = nil
    waiting?.resume()
  }
}
