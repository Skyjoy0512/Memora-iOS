import Foundation

@main
enum RecordingStartChecks {
  @MainActor static func main() async {
    // The real admission code and LocalImportContext execute unchanged. Only
    // the services beyond those boundaries and unrelated state are fixtures.
    for phase in 0...3 {
      for change in 0...5 {
        let model = MemoraModel()
        let project = model.spaces[0]
        let context = LocalImportContext(projectID: project.id, in: model)!
        let invalidate: @MainActor () async -> Void = {
          await Task.yield()
          switch change {
          case 0: model.aiWorkspaceGeneration = UUID() // Personal → team → personal.
          case 1: model.currentTeamID = "another-workspace"
          case 2: model.spaces[0].name = "Renamed"
          case 3: model.spaces = []
          case 4: model.isRestoring = true
          default: model.isStoreProtected = true
          }
        }
        switch phase {
        case 0: await invalidate() // Online sheet dismissed after its context expired.
        case 1: model.beforeRecovery = invalidate
        case 2: model.recorder.beforePermission = invalidate
        default: model.recorder.beforeStart = invalidate
        }
        MediaFiles.deleted = []
        await model.startCapture(spaceID: project.id, context: context)
        precondition(!model.isRecording && !model.isCapturePresented && model.recordingDraft == nil)
        precondition(!model.isPreparingCapture && model.savedDrafts == (phase == 3 ? 1 : 0))
        precondition(model.recorder.starts == (phase == 3 ? 1 : 0))
        precondition(model.recorder.stops == (phase == 3 ? 1 : 0))
        precondition(MediaFiles.deleted.count == (phase == 3 ? 1 : 0))
      }
    }
    let normal = MemoraModel()
    await normal.startCapture(spaceID: normal.spaces[0].id)
    precondition(normal.isRecording && normal.isCapturePresented && normal.savedDrafts == 1)
    precondition(normal.recordingSpaceID == normal.spaces[0].id && !normal.isPreparingCapture)
    precondition(normal.recordingDraft?.audioManifest?.isValid(for: normal.recordingDraft!.id,
      activeFileName: normal.recordingDraft!.fileName) == true)
    await normal.startCapture()
    precondition(normal.recorder.starts == 1)

    let denied = MemoraModel()
    denied.recorder.allowed = false
    await denied.startCapture()
    precondition(denied.microphonePermissionDenied && denied.recorder.starts == 0)

    let recurring = MemoraModel()
    recurring.recurringID = recurring.spaces[0].id
    recurring.recorder.beforePermission = { recurring.spaces[0].name = "Changed while asking" }
    await recurring.startCapture(event: UpcomingMeeting(id: "series", title: "Weekly"))
    precondition(recurring.recorder.starts == 0 && !recurring.isRecording)

    let cancelled = MemoraModel()
    let task = Task { @MainActor in
      await Task.yield()
      await cancelled.startCapture()
    }
    task.cancel()
    await task.value
    precondition(cancelled.recorder.starts == 0 && cancelled.recordingErrorMessage == nil)

    print("RecordingStartChecks: passed (24 stale-context boundaries, normal start/double tap, denied permission, recurring project and cancellation; microphone/session/persistence/UI are fixtures)")
  }
}

struct Meeting { var id: UUID; var spaceID: UUID? }
struct UpcomingMeeting { var id: String; var title: String }

enum AudioRecorderService {
  struct PreparedRecording {
    var manifest: RecordingAudioManifest
    var directory: URL
    var fileURL: URL
  }
}

enum RecordStore {
  static func remove(_ key: String) throws {}
}

@MainActor
final class RecordingStartRecorderFixture {
  var beforePermission: (@MainActor () async -> Void)?
  var beforeStart: (@MainActor () async -> Void)?
  var allowed = true
  var starts = 0
  var stops = 0
  private var prepared = 0
  func requestPermission() async -> Bool { await beforePermission?(); return allowed }
  func prepareRecording() throws -> AudioRecorderService.PreparedRecording {
    prepared += 1
    let id = UUID()
    let name = "fixture-\(prepared).m4a"
    let url = URL(fileURLWithPath: "/fixture/\(name)")
    return .init(manifest: .starting(id: id, fileName: name),
      directory: url.deletingLastPathComponent(), fileURL: url)
  }
  func startContinuous(_ prepared: AudioRecorderService.PreparedRecording,
                       admitRotation: @Sendable (RecordingRotation) async -> Bool) async throws -> URL {
    starts += 1
    await beforeStart?()
    return prepared.fileURL
  }
  func cancelContinuous() { stops += 1 }
  func stop() { stops += 1 }
}

@MainActor enum MediaFiles {
  static var deleted: [URL] = []
  static func delete(_ url: URL?) -> Bool { if let url { deleted.append(url) }; return true }
  static func reference(for url: URL) -> String? { url.lastPathComponent }
}
struct RecordingStartMeterFixture { func reset() {} }
struct RecordingStartTranscriberFixture { func resetHistory() {} }

@MainActor
final class MemoraModel {
  var currentTeamID: String?
  var aiWorkspaceGeneration = UUID()
  var spaces = [MemoraSpace(id: UUID(), name: "Destination", symbol: "folder")]
  var isStoreProtected = false
  var isRestoring = false
  var hasUnsavedRecording = false
  var isPreparingCapture = false
  var isSavingCapture = false
  var isRecording = false
  var isCapturePresented = false
  var microphonePermissionDenied = false
  var recordingErrorMessage: String?
  var deletionFailureMessage: String?
  var recordingURL: URL?
  var recordingStartedAt: Date?
  var recordingPausedAt: Date?
  var recordingPausedDuration: TimeInterval = 0
  var recordingElapsed: TimeInterval = 0
  var captureEvent: UpcomingMeeting?
  var recordingSpaceID: UUID?
  var recordingTitle = ""
  var recordingNote = ""
  var recordingMarkers: [String] = []
  var isRecordingPaused = false
  var recordingDraft: RecordingDraft?
  var recorder = RecordingStartRecorderFixture()
  var levelMeter = RecordingStartMeterFixture()
  var realtimeTranscriber = RecordingStartTranscriberFixture()
  var beforeRecovery: (@MainActor () async -> Void)?
  var recurringID: UUID?
  var savedDrafts = 0
  struct RecordingDraft {
    var id: UUID; var fileName: String; var title: String; var note: String
    var startedAt: Date; var spaceID: UUID?
    var audioManifest: RecordingAudioManifest? = nil
  }
  enum StorageKey { static let recordingDraft = "draft" }
  func space(id: UUID) -> MemoraSpace? { spaces.first { $0.id == id } }
  func retrySavingRecording() async {}
  func resolvePendingRecordingBeforeCapture() async -> Bool { await beforeRecovery?(); return true }
  func recurringProjectID(forEventID: String) -> UUID? { recurringID }
  func persistNow(_ draft: RecordingDraft?, forKey: String) -> Bool { savedDrafts += 1; return true }
  func stopRecorder() { recorder.cancelContinuous(); isRecording = false }
  func admitRecordingRotation(_ rotation: RecordingRotation, generation: UUID) -> Bool { true }
  func resetRecordingClock() { recordingURL = nil }
  func startRecordingTicker() {}
  func startLiveActivity() {}
  func refreshRecordingResources() {}
  func announce(_ message: String) {}
}
