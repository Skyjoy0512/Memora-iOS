import ActivityKit
import Foundation
import Observation

@MainActor
@Observable
final class MemoraModel {
  var selectedTab = RootTab.home
  var homePath: [LibraryRoute] = []
  var libraryPath: [LibraryRoute] = []
  var fileSection = FileSection.meetingFiles
  var isFileCreationPresented = false
  var isSettingsPresented = false
  var isBottomBarHidden = false
  /// Records stay on the device unless Plus turns cloud storage on.
  var cloudStorageEnabled = false {
    didSet { UserDefaults.standard.set(cloudStorageEnabled, forKey: StorageKey.cloudStorage) }
  }
  var meetings: [Meeting] {
    didSet {
      meetingIndex.invalidate()
      meetingSearchTexts.removeAll(keepingCapacity: true)
    }
  }
  var spaces: [MemoraSpace] {
    didSet { spaceIndex.invalidate() }
  }
  var tasks: [MemoraTask] {
    didSet { tasksByMeeting = nil }
  }
  var lifeLogEntries: [LifeLogEntry] {
    didSet { newestEntries = nil }
  }
  var aiHistory: [AIConversationEntry]
  /// People who can be tagged on recordings.
  var people: [Person] = [] {
    didSet { personIndex.invalidate() }
  }
  /// Positions for the array lookups the screens do constantly.
  @ObservationIgnored private var meetingIndex = IdentifiableIndex<Meeting>()
  @ObservationIgnored private var meetingSearchTexts: [UUID: String] = [:]
  @ObservationIgnored private var spaceIndex = IdentifiableIndex<MemoraSpace>()
  @ObservationIgnored private var personIndex = IdentifiableIndex<Person>()
  /// Tasks grouped by the meeting they belong to, built once per change.
  @ObservationIgnored private var tasksByMeeting: [UUID: [MemoraTask]]?
  /// The journal's records newest first, sorted once per change.
  @ObservationIgnored private var newestEntries: [LifeLogEntry]?
  /// Marketplace summary templates the person has added.
  private(set) var installedTemplateIDs: [String] = []
  /// Records that were deleted and can still be brought back.
  private(set) var trashedRecords: [TrashedRecord] = []
  /// Journal entries that were deleted and can still be brought back.
  private(set) var trashedLifeLogEntries: [TrashedLifeLogEntry] = []
  /// The Ask AI chat transcript.
  var aiMessages: [AIChatMessage] = []
  /// What new Ask AI questions look across.
  var aiScope: AIChatScope = .all
  var isAIChatResponding = false
  var isCapturePresented = false
  var isCaptureSourcePresented = false
  var isOnlineMeetingCapturePresented = false
  var isRecording = false
  var isRecordingPaused = false
  /// True while permission is being asked for and the recorder is starting, so
  /// repeated taps cannot begin two recordings.
  private(set) var isPreparingCapture = false
  /// True while a recording is being finished and stored.
  private(set) var isSavingCapture = false
  var recordingElapsed: TimeInterval = 0
  /// Smoothed 0...1 loudness for the recording glow.
  var recordingLevel: Double = 0
  var recordingTitle = ""
  var recordingNote = ""
  var recordingErrorMessage: String?
  /// Explains why a recording paused itself (a call, a lost input), so the
  /// screen matches what actually happened.
  var recordingInterruptionMessage: String?
  var microphonePermissionDenied = false
  var isImporting = false
  var importProgress = 0.0
  var importErrorMessage: String?
  /// Set when stored data exists but could not be read. The data is kept aside
  /// rather than overwritten with samples.
  private(set) var loadFailureMessage: String?
  /// Set when a media file that should have been removed could not be.
  var deletionFailureMessage: String?
  /// Set when a change could not be written to the local store.
  var persistenceFailureMessage: String?
  var account: MemoraAccount?
  var isAuthPresented = false
  var isPaywallPresented = false
  var omiPairingManager = OmiPairingManager()
  var activeDetailMeetingID: UUID?
  /// Meeting details temporarily hide their contextual AI field once people
  /// move into the document.
  var isDetailComposerVisible = true
  /// Bumped by a screen to ask the focused composer to put the keyboard away.
  var composerDismissRequests = 0
  /// How many inline editors are open. The Ask AI field steps aside while the
  /// keyboard belongs to the document being edited.
  var inlineEditingCount = 0
  var isInlineEditing: Bool { inlineEditingCount > 0 }
  /// The inline editor that most recently took focus, so its screen can lift it
  /// clear of the keyboard.
  var focusedInlineEditorID: UUID?
  /// The engine Ask AI and summaries actually use.
  var aiEngine: AIEngine = .automatic {
    didSet {
      UserDefaults.standard.set(aiEngine.rawValue, forKey: StorageKey.aiEngine)
    }
  }

  /// Onboarding runs once. Sign-in and Plus stay optional so people can judge
  /// the app before committing to either.
  private(set) var hasCompletedOnboarding: Bool
  private(set) var isSubscribed: Bool
  private var hasOfferedPlus: Bool

  @ObservationIgnored private var recordingURL: URL?
  @ObservationIgnored private var recordingStartedAt: Date?
  @ObservationIgnored private var recordingPausedAt: Date?
  @ObservationIgnored private var recordingPausedDuration: TimeInterval = 0
  @ObservationIgnored private var recordingTicker: Task<Void, Never>?
  @ObservationIgnored private var levelTicker: Task<Void, Never>?
  @ObservationIgnored private var processingTasks: [UUID: Task<Void, Never>] = [:]
  /// The generation each record's most recent summary request belongs to.
  @ObservationIgnored private var processingRevisions: [UUID: Int] = [:]
  /// Records whose processing was still running the last time the app stopped.
  @ObservationIgnored private var interruptedJobIDs: [String] = []
  /// What a recording in progress would need to be recovered after a stop.
  @ObservationIgnored private var recordingDraft: RecordingDraft?
  @ObservationIgnored private var recordingActivity: Activity<MemoraRecordingAttributes>?
  @ObservationIgnored private var pendingMeetingNavigationID: UUID?
  @ObservationIgnored private let recorder = AudioRecorderService()

  init() {
    let defaults = UserDefaults.standard
    RecordStore.prepare()

    hasCompletedOnboarding = defaults.bool(forKey: StorageKey.hasCompletedOnboarding)
    isSubscribed = defaults.bool(forKey: StorageKey.isSubscribed)
    hasOfferedPlus = defaults.bool(forKey: StorageKey.hasOfferedPlus)
    aiEngine = AIEngine(rawValue: defaults.string(forKey: StorageKey.aiEngine) ?? "") ?? .automatic
    // Cloud storage is a paid option: without Plus the records stay on device.
    cloudStorageEnabled = defaults.bool(forKey: StorageKey.isSubscribed)
      && defaults.bool(forKey: StorageKey.cloudStorage)
    if let data = RecordStore.read(StorageKey.account) {
      account = try? JSONDecoder().decode(MemoraAccount.self, from: data)
    }

    let sample = SampleContent.make()

    /// Reads a document from the local store, moving any legacy `UserDefaults`
    /// copy across on first run. The old value is left in place as a safety
    /// copy, so this can be undone by reverting the build.
    func storedData(forKey key: String) -> Data? {
      RecordStore.read(key)
    }

    // Absent data means a first run, which seeds the demo. Data that exists but
    // cannot be read is set aside rather than replaced, so nothing is lost.
    var didFindUnreadableData = false
    func load<T: Decodable>(_ type: [T].Type, forKey key: String, fallback: [T]) -> [T] {
      guard let data = storedData(forKey: key) else { return fallback }
      if let stored = try? JSONDecoder().decode([T].self, from: data) {
        return stored
      }
      RecordStore.quarantine(data, key: key)
      didFindUnreadableData = true
      return []
    }

    meetings = load([Meeting].self, forKey: StorageKey.meetings, fallback: sample.meetings)
    spaces = load([MemoraSpace].self, forKey: StorageKey.spaces, fallback: sample.spaces)
    lifeLogEntries = load(
      [LifeLogEntry].self,
      forKey: StorageKey.lifeLogEntries,
      fallback: SampleContent.makeLifeLog()
    )
    tasks = load([MemoraTask].self, forKey: StorageKey.tasks, fallback: sample.tasks)
    people = load([Person].self, forKey: StorageKey.people, fallback: SampleContent.makePeople())
    interruptedJobIDs = load([String].self, forKey: StorageKey.activeJobs, fallback: [])
    trashedRecords = load([TrashedRecord].self, forKey: StorageKey.trash, fallback: [])
    trashedLifeLogEntries = load(
      [TrashedLifeLogEntry].self,
      forKey: StorageKey.lifeLogTrash,
      fallback: []
    )
    if let draftData = storedData(forKey: StorageKey.recordingDraft) {
      recordingDraft = try? JSONDecoder().decode(RecordingDraft.self, from: draftData)
    }

    installedTemplateIDs = defaults.stringArray(forKey: StorageKey.installedTemplates) ?? []
    aiHistory = load([AIConversationEntry].self, forKey: StorageKey.aiHistory, fallback: [
      AIConversationEntry(
        id: UUID(),
        question: "今週決まったことは？",
        answer: "録音開始の速さを最優先にし、会議データは既定で端末内に保存する方針です。",
        scopeLabel: "すべての会話",
        createdAt: Calendar.current.date(byAdding: .hour, value: -4, to: .now)!
      )
    ])

    loadFailureMessage = didFindUnreadableData
      ? "保存されたデータの一部を読み込めませんでした。元のデータは端末に退避しています。"
      : nil

    // Anything that was mid-processing when the app stopped is offered for
    // retry instead of looking stuck forever.
    recoverInterruptedJobs()

    // Records kept past their recovery window are removed for good.
    purgeExpiredTrash()

    // A recording that was cut off by a stop is recovered as its own record,
    // never re-recorded.
    Task { await recoverRecordingDraft() }

    // Calls, route changes, and audio resets pause the recording instead of
    // silently losing it.
    recorder.onInterruption = { [weak self] event in
      self?.handleRecorderInterruption(event)
    }
  }

  private func handleRecorderInterruption(_ event: AudioRecorderService.Interruption) {
    guard isRecording else { return }

    switch event {
    case .began:
      isRecordingPaused = true
      recordingPausedAt = .now
      recordingInterruptionMessage = "着信などでマイクが使えなくなり、録音を一時停止しました。「再開」で続けられます。"
    case .ended:
      if recordingInterruptionMessage == nil {
        recordingInterruptionMessage = "マイクが使えるようになりました。「再開」で録音を続けられます。"
      }
    case .inputLost(let reason):
      isRecordingPaused = true
      recordingPausedAt = .now
      recordingInterruptionMessage = reason
    case .reset:
      recordingInterruptionMessage = "オーディオがリセットされました。ここまでの録音を保存します。"
      Task { await stopCapture() }
    }

    updateLiveActivity()
  }

  /// Marks records whose processing was interrupted by a stop or a crash, so the
  /// screen shows a retry rather than a spinner.
  private func recoverInterruptedJobs() {
    guard !interruptedJobIDs.isEmpty else { return }
    let ids = Set(interruptedJobIDs.compactMap(UUID.init(uuidString:)))
    interruptedJobIDs = []
    persistInterruptedJobs()

    var changed = false
    for index in meetings.indices where ids.contains(meetings[index].id) {
      switch meetings[index].status {
      case .importing, .transcribing, .organizing:
        meetings[index].status = .failed("処理が中断されました。音声は保存されています。もう一度試せます。")
        changed = true
      default:
        break
      }
    }
    if changed {
      persistMeetings()
    }
  }

  /// Records whether a record has a processing job running, so an interrupted
  /// one can be recovered on the next launch.
  private func setJobActive(_ id: UUID, active: Bool) {
    if active {
      if !interruptedJobIDs.contains(id.uuidString) {
        interruptedJobIDs.append(id.uuidString)
      }
    } else {
      interruptedJobIDs.removeAll { $0 == id.uuidString }
    }
    persistInterruptedJobs()
  }

  private func persistInterruptedJobs() {
    persistInBackground(interruptedJobIDs, forKey: StorageKey.activeJobs)
  }

  // MARK: - Recording recovery

  /// The minimum needed to bring back a recording the app did not get to save.
  private struct RecordingDraft: Codable {
    var fileName: String
    var title: String
    var note: String
    var startedAt: Date
  }

  /// Writes what a running recording would need if the app stopped now.
  private func persistRecordingDraft() {
    guard let recordingDraft else {
      RecordStore.remove(StorageKey.recordingDraft)
      return
    }
    persistInBackground(recordingDraft, forKey: StorageKey.recordingDraft)
  }

  /// Brings back a recording that was interrupted: its audio becomes a record
  /// awaiting transcription, or, when no audio survived, the note becomes a
  /// memo. Recording is never restarted on its own.
  private func recoverRecordingDraft() async {
    guard let draft = recordingDraft else { return }
    recordingDraft = nil
    persistRecordingDraft()

    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let audioURL = MediaFiles.resolve(draft.fileName),
          FileManager.default.fileExists(atPath: audioURL.path) else {
      if !note.isEmpty {
        addLifeLogEntry(
          kind: .memo,
          title: title.isEmpty ? "復旧したメモ" : title,
          summary: note,
          createdAt: draft.startedAt,
          photoData: nil,
          eventDate: nil,
          locationName: nil
        )
      }
      return
    }

    let duration = await MediaFiles.duration(of: audioURL) ?? 1
    var meeting = Meeting(
      id: UUID(),
      title: title.isEmpty ? "復旧した録音" : title,
      createdAt: draft.startedAt,
      duration: duration,
      source: .recording,
      status: .waitingForTranscription,
      summary: "アプリが中断する前に録音していた音声を復旧しました。文字起こしを開始できます。",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: [],
      spaceID: nil,
      audioURL: audioURL
    )
    meeting.notes = note
    meetings.insert(meeting, at: 0)
    persistMeetings()

    lifeLogEntries.insert(
      LifeLogEntry(
        id: UUID(),
        createdAt: draft.startedAt,
        title: meeting.title,
        summary: "中断前に録音していた音声を復旧しました。",
        source: .iphone,
        meetingID: meeting.id
      ),
      at: 0
    )
    persistLifeLog()
  }

  // MARK: - Onboarding and account

  func dismissLoadFailure() {
    loadFailureMessage = nil
  }

  func completeOnboarding() {
    hasCompletedOnboarding = true
    UserDefaults.standard.set(true, forKey: StorageKey.hasCompletedOnboarding)
  }

  func replayOnboarding() {
    hasCompletedOnboarding = false
    UserDefaults.standard.set(false, forKey: StorageKey.hasCompletedOnboarding)
  }

  var isSignedIn: Bool {
    account != nil
  }

  func signIn(with provider: AuthProvider, email: String? = nil, displayName: String? = nil) {
    let address = email ?? Self.placeholderEmail(for: provider)
    persistAccount(
      MemoraAccount(
        displayName: displayName ?? Self.placeholderName(for: provider, email: address),
        email: address,
        provider: provider,
        createdAt: account?.createdAt ?? .now
      )
    )
  }

  func signOut() {
    persistAccount(nil)
  }

  func deleteAccount() {
    persistAccount(nil)
    aiHistory = []
  }

  /// Purchases are tied to the Apple ID, so Plus does not require a Memora
  /// account. Signing in only adds sync.
  func startSubscription() {
    isSubscribed = true
    UserDefaults.standard.set(true, forKey: StorageKey.isSubscribed)
  }

  /// Turns cloud storage on or off. It stays off without Plus, so the records
  /// remain local unless the paid option is active.
  func setCloudStorageEnabled(_ enabled: Bool) {
    cloudStorageEnabled = isSubscribed && enabled
  }

  /// Offers Plus once, and only after someone has seen a conversation get
  /// organized, so the value is visible before the price is.
  private func offerPlusIfNeeded() {
    guard !hasOfferedPlus, !isSubscribed else { return }
    hasOfferedPlus = true
    UserDefaults.standard.set(true, forKey: StorageKey.hasOfferedPlus)
    isPaywallPresented = true
  }

  private func persistAccount(_ account: MemoraAccount?) {
    self.account = account
    if let account, RecordStore.saveNow(account, key: StorageKey.account) {
      // The legacy copy is only cleared once the store has it.
      UserDefaults.standard.removeObject(forKey: StorageKey.account)
    } else if account == nil {
      RecordStore.remove(StorageKey.account)
      UserDefaults.standard.removeObject(forKey: StorageKey.account)
    }
  }

  private static func placeholderEmail(for provider: AuthProvider) -> String {
    switch provider {
    case .apple:
      "you@privaterelay.appleid.com"
    case .google:
      "you@gmail.com"
    case .email:
      "you@example.com"
    }
  }

  private static func placeholderName(for provider: AuthProvider, email: String) -> String {
    switch provider {
    case .apple, .google:
      provider.label + "ユーザー"
    case .email:
      String(email.prefix(while: { $0 != "@" }))
    }
  }

  // MARK: - Content

  func meeting(id: UUID) -> Meeting? {
    meetingIndex.element(id, in: meetings)
  }

  /// The text a record is matched against while searching: the same fields on
  /// every screen — title, notes, summary, transcript, and the extracted
  /// sections. It is joined once and reused, so typing does not rebuild every
  /// transcript on each keystroke.
  func searchText(for meeting: Meeting) -> String {
    if let cached = meetingSearchTexts[meeting.id] { return cached }

    let parts = [meeting.title, meeting.notes, meeting.summary]
      + meeting.decisions
      + meeting.openQuestions
      + meeting.keyPoints
      + meeting.transcript.map(\.text)

    let text = parts.joined(separator: "\n")
    meetingSearchTexts[meeting.id] = text
    return text
  }

  /// The tasks attached to one meeting, grouped once per change.
  func tasks(forMeeting id: UUID) -> [MemoraTask] {
    if tasksByMeeting == nil {
      var grouped: [UUID: [MemoraTask]] = [:]
      for task in tasks {
        guard let meetingID = task.meetingID else { continue }
        grouped[meetingID, default: []].append(task)
      }
      tasksByMeeting = grouped
    }
    return tasksByMeeting?[id] ?? []
  }

  /// The journal's records, newest first, sorted once per change.
  var newestLifeLogEntries: [LifeLogEntry] {
    if let newestEntries { return newestEntries }
    let sorted = lifeLogEntries.sorted { $0.createdAt > $1.createdAt }
    newestEntries = sorted
    return sorted
  }

  func space(id: UUID) -> MemoraSpace? {
    spaceIndex.element(id, in: spaces)
  }

  func startCapture() async {
    // Starting twice (a double tap, or two entry points) must not begin two
    // recordings, so a start already under way wins.
    guard !isPreparingCapture, !isSavingCapture else { return }
    guard !isRecording else {
      isCapturePresented = true
      return
    }

    isPreparingCapture = true
    defer { isPreparingCapture = false }

    let allowed = await recorder.requestPermission()
    guard allowed else {
      microphonePermissionDenied = true
      return
    }
    // The permission sheet can take a moment; re-check before starting.
    guard !isRecording, !isSavingCapture else { return }

    do {
      recordingURL = try recorder.start()
      recordingStartedAt = .now
      recordingPausedAt = nil
      recordingPausedDuration = 0
      recordingElapsed = 0
      recordingTitle = ""
      recordingNote = ""
      isRecordingPaused = false
      isRecording = true
      isCapturePresented = true
      recordingLevel = 0
      startRecordingTicker()
      startLevelTicker()
      startLiveActivity()
      if let recordingURL, let fileName = MediaFiles.reference(for: recordingURL) {
        recordingDraft = RecordingDraft(fileName: fileName, title: "", note: "", startedAt: .now)
        persistRecordingDraft()
      }
    } catch {
      recordingErrorMessage = error.localizedDescription
    }
  }

  func stopCapture() async {
    guard isRecording, !isSavingCapture else { return }
    isSavingCapture = true
    defer { isSavingCapture = false }

    recorder.stop()
    recordingTicker?.cancel()
    recordingTicker = nil
    levelTicker?.cancel()
    levelTicker = nil
    recordingLevel = 0
    isRecording = false
    isRecordingPaused = false
    await endLiveActivity()

    var meeting = Meeting(
      id: UUID(),
      title: recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "新しい会話"
        : recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines),
      createdAt: .now,
      duration: max(recordingElapsed, 1),
      source: .recording,
      status: .transcribing(0.12),
      summary: "録音を保存しました。文字起こしを準備しています。",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: [],
      spaceID: nil,
      audioURL: recordingURL
    )
    meeting.notes = recordingNote
    meetings.insert(meeting, at: 0)
    persistMeetings()
    lifeLogEntries.insert(
      LifeLogEntry(
        id: UUID(),
        createdAt: meeting.createdAt,
        title: meeting.title,
        summary: "iPhoneで新しい音声を記録しました。",
        source: .iphone,
        meetingID: meeting.id
      ),
      at: 0
    )
    persistLifeLog()
    recordingDraft = nil
    persistRecordingDraft()
    recordingInterruptionMessage = nil
    recordingURL = nil
    recordingStartedAt = nil
    recordingPausedAt = nil
    recordingPausedDuration = 0
    recordingTitle = ""
    recordingNote = ""
    selectedTab = .files
    fileSection = .meetingFiles
    pendingMeetingNavigationID = meeting.id
    isCapturePresented = false
    beginProcessing(meeting.id)
  }

  func completeCaptureDismissal() {
    // The sheet can be closed while recording continues, so remember what was
    // typed in case the app does not get to save.
    if isRecording, recordingDraft != nil {
      recordingDraft?.title = recordingTitle
      recordingDraft?.note = recordingNote
      persistRecordingDraft()
    }

    guard let meetingID = pendingMeetingNavigationID else { return }
    pendingMeetingNavigationID = nil
    selectedTab = .files
    libraryPath = [.meeting(meetingID)]
  }

  func cancelCapture() async {
    recorder.stop()
    recordingTicker?.cancel()
    recordingTicker = nil
    levelTicker?.cancel()
    levelTicker = nil
    recordingLevel = 0
    isRecording = false
    isRecordingPaused = false
    isCapturePresented = false
    // Discarding means the audio goes too; nothing is kept for the journal.
    recordingDraft = nil
    persistRecordingDraft()
    recordingInterruptionMessage = nil
    if !MediaFiles.delete(recordingURL) {
      deletionFailureMessage = "録音ファイルを削除できませんでした。ストレージの空き容量を確認してください。"
    }
    recordingURL = nil
    recordingStartedAt = nil
    recordingPausedAt = nil
    recordingPausedDuration = 0
    await endLiveActivity()
  }

  func toggleCapturePause() {
    guard isRecording else { return }
    if isRecordingPaused {
      guard recorder.resume() else {
        recordingErrorMessage = "録音を再開できませんでした。"
        return
      }
      if let recordingPausedAt {
        recordingPausedDuration += Date.now.timeIntervalSince(recordingPausedAt)
      }
      self.recordingPausedAt = nil
      isRecordingPaused = false
      recordingInterruptionMessage = nil
    } else {
      recorder.pause()
      recordingPausedAt = .now
      isRecordingPaused = true
    }
    updateLiveActivity()
  }

  func importAudio(from sourceURL: URL) async {
    isImporting = true
    importProgress = 0.08
    importErrorMessage = nil

    let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if hasSecurityScope {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let directory = try recordingsDirectory()
      let fileName = sourceURL.deletingPathExtension().lastPathComponent
      let destination = directory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(sourceURL.pathExtension)
      try FileManager.default.copyItem(at: sourceURL, to: destination)
      importProgress = 0.72
      try? await Task.sleep(for: .milliseconds(450))

      let meeting = Meeting(
        id: UUID(),
        title: fileName.isEmpty ? "インポートした音声" : fileName,
        createdAt: .now,
        duration: 0,
        source: .importFile,
        status: .waitingForTranscription,
        summary: "音声を保存しました。必要な時に文字起こしを開始できます。",
        keyPoints: [],
        decisions: [],
        openQuestions: [],
        transcript: [],
        spaceID: nil,
        audioURL: destination
      )
      meetings.insert(meeting, at: 0)
      persistMeetings()
      importProgress = 1
      try? await Task.sleep(for: .milliseconds(350))
      isImporting = false
      selectedTab = .files
      fileSection = .meetingFiles
      libraryPath = [.meeting(meeting.id)]
    } catch {
      isImporting = false
      importErrorMessage = "音声を読み込めませんでした。ファイル形式と空き容量を確認してください。"
    }
  }

  func importAIAttachment(from sourceURL: URL) throws -> AIAttachment {
    let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if hasSecurityScope {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let directory = base.appendingPathComponent("AIAttachments", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(sourceURL.pathExtension)
    try FileManager.default.copyItem(at: sourceURL, to: destination)
    return AIAttachment(id: UUID(), name: sourceURL.lastPathComponent, url: destination)
  }

  func importAIPhoto(data: Data, fileExtension: String) throws -> AIAttachment {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let directory = base.appendingPathComponent("AIAttachments", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let safeExtension = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
    let resolvedExtension = safeExtension.isEmpty ? "jpg" : safeExtension
    let fileName = "写真-\(UUID().uuidString.prefix(8)).\(resolvedExtension)"
    let destination = directory.appendingPathComponent(fileName)
    try data.write(to: destination, options: .atomic)
    return AIAttachment(id: UUID(), name: fileName, url: destination)
  }

  func retryProcessing(_ id: UUID) {
    updateMeeting(id) { meeting in
      meeting.status = .transcribing(0.08)
    }
    beginProcessing(id)
  }

  func startImportedTranscription(_ id: UUID) {
    guard let meeting = meeting(id: id), meeting.source == .importFile else { return }
    updateMeeting(id) { $0.status = .transcribing(0.08) }
    processingTasks[id]?.cancel()
    processingTasks[id] = Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: .milliseconds(600))
      guard !Task.isCancelled else { return }
      self.updateMeeting(id) { $0.status = .transcribing(0.62) }

      let outcome = await TranscriptionService.transcribe(fileURL: self.meeting(id: id)?.audioURL)
      guard !Task.isCancelled else { return }

      self.updateMeeting(id) { meeting in
        if case .segments(let segments) = outcome {
          meeting.transcript = segments
        } else {
          meeting.transcript = SampleContent.generatedTranscript
        }
        meeting.status = .waitingForSummary
      }
    }
  }

  /// Rewrites the summary from the real transcript with the chosen template.
  /// Nothing is invented: when no engine can answer, the record says so and
  /// keeps whatever the person had, rather than filling in sample text.
  func generateSummary(_ id: UUID, choice: SummaryTemplateChoice) {
    guard let meeting = meeting(id: id), !meeting.transcript.isEmpty else { return }

    let revision = bumpProcessingRevision(for: id)
    updateMeeting(id) { $0.status = .organizing(choice.processingLabel) }
    processingTasks[id]?.cancel()
    setJobActive(id, active: true)

    processingTasks[id] = Task { [weak self] in
      guard let self else { return }

      let transcript = meeting.transcript
        .map { "\($0.speaker): \($0.text)" }
        .joined(separator: "\n")
      let summary = await AIEngineService.answer(
        question: choice.summaryInstruction,
        scopeLabel: "文字起こし",
        context: transcript
      )

      // A newer request or a deleted record makes this result stale.
      guard !Task.isCancelled,
            self.processingRevision(for: id) == revision,
            self.meeting(id: id) != nil else { return }

      if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        self.updateMeeting(id) { meeting in
          meeting.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
          meeting.status = .ready
        }
        self.offerPlusIfNeeded()
      } else {
        self.updateMeeting(id) {
          $0.status = .failed("要約を生成できませんでした。AIエンジンとキーを確認して再試行してください。")
        }
      }

      self.processingTasks[id] = nil
      self.setJobActive(id, active: false)
    }
  }

  // MARK: - Processing revisions

  /// Bumped for each new summary request, so an older result cannot overwrite a
  /// newer edit or a deleted record.
  private func bumpProcessingRevision(for id: UUID) -> Int {
    let next = (processingRevisions[id] ?? 0) + 1
    processingRevisions[id] = next
    return next
  }

  private func processingRevision(for id: UUID) -> Int {
    processingRevisions[id] ?? 0
  }

  // MARK: - Summary templates

  /// Templates added from the marketplace, in catalog order.
  var installedMarketTemplates: [SummaryMarketTemplate] {
    SummaryTemplateCatalog.market.filter { installedTemplateIDs.contains($0.id) }
  }

  func installTemplate(_ id: String) {
    guard !installedTemplateIDs.contains(id) else { return }
    installedTemplateIDs.append(id)
    persistInstalledTemplates()
  }

  func uninstallTemplate(_ id: String) {
    installedTemplateIDs.removeAll { $0 == id }
    persistInstalledTemplates()
  }

  private func persistInstalledTemplates() {
    UserDefaults.standard.set(installedTemplateIDs, forKey: StorageKey.installedTemplates)
  }

  func toggleTask(_ id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[index].isCompleted.toggle()
    persistTasks()
  }

  func updateTask(
    _ id: UUID,
    title: String,
    assignee: String,
    dueDate: Date?,
    meetingID: UUID?
  ) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }
    let trimmedAssignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines)

    tasks[index].title = trimmedTitle
    tasks[index].assignee = trimmedAssignee.isEmpty ? nil : trimmedAssignee
    tasks[index].dueDate = dueDate
    tasks[index].meetingID = meetingID
    persistTasks()
  }

  func deleteTask(_ id: UUID) {
    tasks.removeAll { $0.id == id }
    persistTasks()
  }

  func addTask(title: String, assignee: String, dueDate: Date?) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }
    let trimmedAssignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
    tasks.insert(
      MemoraTask(
        id: UUID(),
        title: trimmedTitle,
        meetingID: nil,
        assignee: trimmedAssignee.isEmpty ? nil : trimmedAssignee,
        dueDate: dueDate,
        isCompleted: false
      ),
      at: 0
    )
    persistTasks()
  }

  func addSpace(name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    spaces.insert(MemoraSpace(id: UUID(), name: trimmed, symbol: "folder"), at: 0)
    persistSpaces()
  }

  func renameSpace(_ id: UUID, name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
    spaces[index].name = trimmed
    persistSpaces()
  }

  /// Removes a project. Its records are kept and become uncategorized.
  func deleteSpace(_ id: UUID) {
    guard spaces.contains(where: { $0.id == id }) else { return }
    spaces.removeAll { $0.id == id }
    persistSpaces()

    for index in meetings.indices where meetings[index].spaceID == id {
      meetings[index].spaceID = nil
    }
    persistMeetings()
  }

  /// Files a record under a project, or takes it out of every project.
  func setSpace(_ spaceID: UUID?, forMeeting meetingID: UUID) {
    updateMeeting(meetingID) { $0.spaceID = spaceID }
  }

  func addLifeLogEntry(
    kind: LifeLogKind,
    title: String,
    summary: String,
    createdAt: Date,
    photoData: Data?,
    eventDate: Date?,
    locationName: String?
  ) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedLocation = locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedTitle: String
    if !trimmedTitle.isEmpty {
      resolvedTitle = trimmedTitle
    } else if kind == .location, let trimmedLocation, !trimmedLocation.isEmpty {
      resolvedTitle = "\(trimmedLocation)に到着"
    } else {
      resolvedTitle = kind.label
    }

    // Photos live in the media folder; the entry keeps the file name.
    let photoFileName = photoData.flatMap { MediaFiles.writePhoto($0) }

    lifeLogEntries.insert(
      LifeLogEntry(
        id: UUID(),
        createdAt: createdAt,
        title: resolvedTitle,
        summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
        source: .iphone,
        meetingID: nil,
        kind: kind,
        photoFileName: photoFileName,
        eventDate: eventDate,
        locationName: trimmedLocation
      ),
      at: 0
    )
    persistLifeLog()
  }

  func renameMeeting(_ id: UUID, title: String) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    updateMeeting(id) { $0.title = trimmed }
  }

  func updateMeetingNotes(_ id: UUID, notes: String) {
    updateMeeting(id) { $0.notes = notes }
  }

  func updateMeetingSummary(_ id: UUID, summary: String) {
    updateMeeting(id) { $0.summary = summary }
  }

  func updateMeetingList(_ id: UUID, _ keyPath: WritableKeyPath<Meeting, [String]>, items: [String]) {
    updateMeeting(id) { $0[keyPath: keyPath] = items }
  }

  func renameSpeaker(meetingID: UUID, segmentID: UUID, name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let meetingIndex = meetings.firstIndex(where: { $0.id == meetingID }),
          let segmentIndex = meetings[meetingIndex].transcript.firstIndex(where: { $0.id == segmentID }) else { return }
    meetings[meetingIndex].transcript[segmentIndex].speaker = trimmed
    meetings[meetingIndex].transcript[segmentIndex].speakerIsCertain = true
    persistMeetings()
  }

  /// Corrects the body of one transcript segment, leaving the speaker as is.
  func updateTranscriptSegment(meetingID: UUID, segmentID: UUID, text: String) {
    guard let meetingIndex = meetings.firstIndex(where: { $0.id == meetingID }),
          let segmentIndex = meetings[meetingIndex].transcript.firstIndex(where: { $0.id == segmentID }) else { return }
    meetings[meetingIndex].transcript[segmentIndex].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    persistMeetings()
  }

  /// Moves a record to the trash. Its audio, tasks, and journal entries are kept
  /// so it can be restored exactly, and removed only when the trash is emptied.
  func deleteMeeting(_ id: UUID) {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }

    processingTasks[id]?.cancel()
    processingTasks[id] = nil
    processingRevisions[id] = nil
    setJobActive(id, active: false)

    let removed = meetings.remove(at: index)
    let removedTasks = tasks.filter { $0.meetingID == id }
    let removedEntries = lifeLogEntries.filter { $0.meetingID == id }
    tasks.removeAll { $0.meetingID == id }
    lifeLogEntries.removeAll { $0.meetingID == id }

    trashedRecords.insert(
      TrashedRecord(
        meeting: removed,
        tasks: removedTasks,
        lifeLogEntries: removedEntries,
        deletedAt: .now
      ),
      at: 0
    )

    persistMeetings()
    persistTasks()
    persistLifeLog()
    persistTrash()
  }

  /// Puts a trashed record back exactly as it was.
  func restoreTrashedRecord(_ id: UUID) {
    guard let index = trashedRecords.firstIndex(where: { $0.id == id }) else { return }
    let record = trashedRecords.remove(at: index)

    meetings.insert(record.meeting, at: 0)
    if !record.tasks.isEmpty {
      tasks.insert(contentsOf: record.tasks, at: 0)
    }
    if !record.lifeLogEntries.isEmpty {
      lifeLogEntries.append(contentsOf: record.lifeLogEntries)
    }

    persistMeetings()
    persistTasks()
    persistLifeLog()
    persistTrash()
  }

  /// Removes a trashed record and its audio for good.
  func permanentlyDeleteTrashedRecord(_ id: UUID) {
    guard let index = trashedRecords.firstIndex(where: { $0.id == id }) else { return }
    let record = trashedRecords.remove(at: index)
    persistTrash()

    for name in record.meeting.photoFileNames ?? [] {
      MediaFiles.deletePhoto(name)
    }
    if !MediaFiles.delete(record.meeting.audioURL) {
      deletionFailureMessage = "音声ファイルを削除できませんでした。ストレージの空き容量を確認してください。"
    }
  }

  /// Drops trashed records once their recovery window has passed.
  private func purgeExpiredTrash() {
    let cutoff = Date().addingTimeInterval(-TrashedRecord.lifetime)

    let expiredRecords = trashedRecords.filter { $0.deletedAt < cutoff }
    if !expiredRecords.isEmpty {
      for record in expiredRecords {
        for name in record.meeting.photoFileNames ?? [] {
          MediaFiles.deletePhoto(name)
        }
        MediaFiles.delete(record.meeting.audioURL)
      }
      trashedRecords.removeAll { $0.deletedAt < cutoff }
      persistTrash()
    }

    let expiredEntries = trashedLifeLogEntries.filter { $0.deletedAt < cutoff }
    if !expiredEntries.isEmpty {
      for record in expiredEntries {
        if let name = record.entry.photoFileName {
          MediaFiles.deletePhoto(name)
        }
      }
      trashedLifeLogEntries.removeAll { $0.deletedAt < cutoff }
      persistLifeLogTrash()
    }
  }

  // MARK: - Journal entries

  func updateLifeLogEntry(_ id: UUID, title: String, summary: String, createdAt: Date) {
    guard let index = lifeLogEntries.firstIndex(where: { $0.id == id }) else { return }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }

    lifeLogEntries[index].title = trimmedTitle
    lifeLogEntries[index].summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    lifeLogEntries[index].createdAt = createdAt
    persistLifeLog()
  }

  /// Moves an entry to the trash. Its photo stays until it is removed for good.
  func deleteLifeLogEntry(_ id: UUID) {
    guard let index = lifeLogEntries.firstIndex(where: { $0.id == id }) else { return }
    let removed = lifeLogEntries.remove(at: index)
    trashedLifeLogEntries.insert(TrashedLifeLogEntry(entry: removed, deletedAt: .now), at: 0)
    persistLifeLog()
    persistLifeLogTrash()
  }

  func restoreTrashedLifeLogEntry(_ id: UUID) {
    guard let index = trashedLifeLogEntries.firstIndex(where: { $0.id == id }) else { return }
    let record = trashedLifeLogEntries.remove(at: index)
    lifeLogEntries.append(record.entry)
    persistLifeLog()
    persistLifeLogTrash()
  }

  func permanentlyDeleteTrashedLifeLogEntry(_ id: UUID) {
    guard let index = trashedLifeLogEntries.firstIndex(where: { $0.id == id }) else { return }
    let record = trashedLifeLogEntries.remove(at: index)
    persistLifeLogTrash()

    if let name = record.entry.photoFileName {
      MediaFiles.deletePhoto(name)
    }
  }

  private func persistLifeLogTrash() {
    persistInBackground(trashedLifeLogEntries, forKey: StorageKey.lifeLogTrash)
  }

  private func persistTrash() {
    persistInBackground(trashedRecords, forKey: StorageKey.trash)
  }

  // MARK: - Backup

  func persistAIHistory() {
    persistInBackground(aiHistory, forKey: StorageKey.aiHistory)
  }

  /// True when a restore would not overwrite anything of the person's own.
  var isEmpty: Bool {
    meetings.isEmpty
      && spaces.isEmpty
      && tasks.isEmpty
      && lifeLogEntries.isEmpty
      && people.isEmpty
  }

  /// Writes a versioned package of the records and their media into `directory`.
  func makeBackupPackage() throws -> URL {
    try BackupPackage.write(
      meetings: meetings,
      spaces: spaces,
      tasks: tasks,
      lifeLogEntries: lifeLogEntries,
      people: people,
      aiHistory: aiHistory,
      into: FileManager.default.temporaryDirectory
    )
  }

  /// Restores a package. It refuses to run when this device already holds
  /// records, so a backup can never silently replace them.
  func restoreBackup(from packageURL: URL) throws {
    guard isEmpty else { throw BackupPackage.BackupError.notEmpty }

    let manifest = try BackupPackage.read(from: packageURL)
    try BackupPackage.install(mediaFrom: packageURL, manifest: manifest)

    meetings = manifest.meetings
    spaces = manifest.spaces
    tasks = manifest.tasks
    lifeLogEntries = manifest.lifeLogEntries
    people = manifest.people
    aiHistory = manifest.aiHistory

    persistMeetings()
    persistSpaces()
    persistTasks()
    persistLifeLog()
    persistPeople()
    persistAIHistory()
  }

  /// The photos attached to a record, read back from the media folder.
  func meetingPhotos(_ id: UUID) -> [Data] {
    (meeting(id: id)?.photoFileNames ?? []).compactMap { MediaFiles.photoData($0) }
  }

  func addMeetingPhoto(_ id: UUID, data: Data) {
    guard let name = MediaFiles.writePhoto(data) else {
      persistenceFailureMessage = "写真を保存できませんでした。ストレージの空き容量を確認してください。"
      return
    }
    updateMeeting(id) { meeting in
      var names = meeting.photoFileNames ?? []
      names.append(name)
      meeting.photoFileNames = names
    }
  }

  func removeMeetingPhoto(_ id: UUID, index: Int) {
    var removed: String?
    updateMeeting(id) { meeting in
      var names = meeting.photoFileNames ?? []
      guard names.indices.contains(index) else { return }
      removed = names.remove(at: index)
      meeting.photoFileNames = names.isEmpty ? nil : names
    }
    if let removed {
      MediaFiles.deletePhoto(removed)
    }
  }

  // MARK: - People

  func person(id: UUID) -> Person? {
    personIndex.element(id, in: people)
  }

  func persistPeople() {
    persistInBackground(people, forKey: StorageKey.people)
  }

  func resetSampleContent() {
    let sample = SampleContent.make()
    meetings = sample.meetings
    spaces = sample.spaces
    persistMeetings()
    persistSpaces()
    lifeLogEntries = SampleContent.makeLifeLog()
    persistLifeLog()
    tasks = sample.tasks
    persistTasks()
    people = SampleContent.makePeople()
    persistPeople()
    aiHistory = []
    aiMessages = []
    homePath = []
    libraryPath = []
    selectedTab = .home
  }

  func removeAllContent() {
    meetings = []
    lifeLogEntries = []
    persistLifeLog()
    tasks = []
    persistTasks()
    people = []
    persistPeople()
    aiHistory = []
    aiMessages = []
    spaces = []
    persistMeetings()
    persistSpaces()
    homePath = []
    libraryPath = []
  }

  func handle(_ url: URL) async {
    guard url.scheme == "memora" else { return }

    if url.host == "meeting" {
      if let id = UUID(uuidString: url.lastPathComponent) {
        selectedTab = .files
        fileSection = .meetingFiles
        libraryPath = [.meeting(id)]
      }
      return
    }

    selectedTab = .files
    libraryPath = []
    if url.host == "capture" {
      await startCapture()
    } else if url.host == "recording", isRecording {
      isCapturePresented = true
    }
  }

  private func startRecordingTicker() {
    recordingTicker?.cancel()
    recordingTicker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self, let startedAt = self.recordingStartedAt else { return }
        let currentPause = self.recordingPausedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        self.recordingElapsed = max(0, Date.now.timeIntervalSince(startedAt) - self.recordingPausedDuration - currentPause)
      }
    }
  }

  /// Samples the recorder at ~22Hz so the glow can follow the voice.
  private func startLevelTicker() {
    levelTicker?.cancel()
    levelTicker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(45))
        guard let self else { return }
        let target = self.isRecordingPaused ? 0 : self.recorder.level()
        let rate = target > self.recordingLevel ? 0.6 : 0.12
        self.recordingLevel += (target - self.recordingLevel) * rate
      }
    }
  }

  private func beginProcessing(_ id: UUID) {
    processingTasks[id]?.cancel()
    setJobActive(id, active: true)
    processingTasks[id] = Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: .milliseconds(700))
      guard !Task.isCancelled else { return }
      self.updateMeeting(id) { $0.status = .transcribing(0.58) }

      // Only a real engine's transcript is ever stored. When none can run, the
      // record says so and keeps the audio for a retry — never sample text.
      let outcome = await TranscriptionService.transcribe(fileURL: self.meeting(id: id)?.audioURL)
      guard !Task.isCancelled else { return }

      switch outcome {
      case .segments(let segments):
        self.updateMeeting(id) { meeting in
          meeting.transcript = segments
          meeting.status = .waitingForSummary
        }
      case .unavailable:
        self.updateMeeting(id) {
          $0.status = .failed("この端末では文字起こしを利用できません。音声は保存されています。設定で別のエンジンを選ぶか、別の端末でお試しください。")
        }
      case .failed(let message):
        self.updateMeeting(id) { $0.status = .failed(message) }
      }

      self.processingTasks[id] = nil
      self.setJobActive(id, active: false)
    }
  }

  private func updateMeeting(_ id: UUID, change: (inout Meeting) -> Void) {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
    change(&meetings[index])
    persistMeetings()
  }

  private func persistTasks() {
    persistInBackground(tasks, forKey: StorageKey.tasks)
  }

  private func persistLifeLog() {
    persistInBackground(lifeLogEntries, forKey: StorageKey.lifeLogEntries)
  }

  func persistMeetings() {
    persistInBackground(meetings, forKey: StorageKey.meetings)
  }

  private func persistSpaces() {
    persistInBackground(spaces, forKey: StorageKey.spaces)
  }

  private func persistInBackground<T: Encodable & Sendable>(_ value: T, forKey key: String) {
    RecordStore.save(value, key: key) { [weak self] in
      self?.persistenceFailureMessage = "データを保存できませんでした。ストレージの空き容量を確認してください。"
    }
  }

  private enum StorageKey {
    static let hasCompletedOnboarding = "hasSeenMemoraWelcome"
    static let hasOfferedPlus = "hasOfferedMemoraPlus"
    static let isSubscribed = "memoraPlusActive"
    static let account = "memoraAccount"
    static let tasks = "memoraTasks"
    static let lifeLogEntries = "memoraLifeLogEntries"
    static let meetings = "memoraMeetings"
    static let spaces = "memoraSpaces"
    static let aiEngine = "memora.aiEngine"
    static let people = "memoraPeople"
    static let installedTemplates = "memoraInstalledTemplates"
    static let cloudStorage = "memoraCloudStorage"
    static let activeJobs = "memoraActiveJobs"
    static let recordingDraft = "memoraRecordingDraft"
    static let trash = "memoraTrash"
    static let lifeLogTrash = "memoraLifeLogTrash"
    static let aiHistory = "memoraAIHistory"
  }

  private func recordingsDirectory() throws -> URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let directory = base.appendingPathComponent("Recordings", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func startLiveActivity() {
    guard ActivityAuthorizationInfo().areActivitiesEnabled,
          let startedAt = recordingStartedAt else { return }
    let attributes = MemoraRecordingAttributes(title: "Memoraで録音中")
    let state = MemoraRecordingAttributes.ContentState(startedAt: startedAt, isPaused: false)
    let content = ActivityContent(state: state, staleDate: nil)
    recordingActivity = try? Activity.request(attributes: attributes, content: content)
  }

  private func updateLiveActivity() {
    guard let recordingActivity, let startedAt = recordingStartedAt else { return }
    let state = MemoraRecordingAttributes.ContentState(startedAt: startedAt, isPaused: isRecordingPaused)
    let content = ActivityContent(state: state, staleDate: nil)
    Task {
      await recordingActivity.update(content)
    }
  }

  private func endLiveActivity() async {
    guard let recordingActivity else { return }
    let startedAt = recordingStartedAt ?? .now
    let state = MemoraRecordingAttributes.ContentState(startedAt: startedAt, isPaused: false)
    let content = ActivityContent(state: state, staleDate: nil)
    await recordingActivity.end(content, dismissalPolicy: .immediate)
    self.recordingActivity = nil
  }
}
