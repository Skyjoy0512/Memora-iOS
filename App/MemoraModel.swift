import ActivityKit
import Foundation
import Observation

@MainActor
@Observable
final class MemoraModel {
  var selectedTab = RootTab.files
  var libraryPath: [LibraryRoute] = []
  var fileSection = FileSection.meetingFiles
  var isFileSidebarPresented = false
  var isFileCreationPresented = false
  var isBottomBarCompact = false
  var meetings: [Meeting]
  var spaces: [MemoraSpace]
  var tasks: [MemoraTask]
  var lifeLogEntries: [LifeLogEntry]
  var aiHistory: [AIConversationEntry]
  var isCapturePresented = false
  var isCaptureSourcePresented = false
  var isRecording = false
  var isRecordingPaused = false
  var recordingElapsed: TimeInterval = 0
  var recordingTitle = ""
  var recordingNote = ""
  var recordingErrorMessage: String?
  var microphonePermissionDenied = false
  var isImporting = false
  var importProgress = 0.0
  var importErrorMessage: String?
  var account: MemoraAccount?
  var isAuthPresented = false
  var isPaywallPresented = false
  var omiPairingManager = OmiPairingManager()
  var activeDetailMeetingID: UUID?
  /// Meeting details temporarily hide their contextual AI field once people
  /// move into the document.
  var isDetailComposerVisible = true

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
  @ObservationIgnored private var processingTasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var recordingActivity: Activity<MemoraRecordingAttributes>?
  @ObservationIgnored private var pendingMeetingNavigationID: UUID?
  @ObservationIgnored private let recorder = AudioRecorderService()

  init() {
    let defaults = UserDefaults.standard
    hasCompletedOnboarding = defaults.bool(forKey: StorageKey.hasCompletedOnboarding)
    isSubscribed = defaults.bool(forKey: StorageKey.isSubscribed)
    hasOfferedPlus = defaults.bool(forKey: StorageKey.hasOfferedPlus)
    if let data = defaults.data(forKey: StorageKey.account) {
      account = try? JSONDecoder().decode(MemoraAccount.self, from: data)
    }

    let sample = SampleContent.make()
    if let meetingData = defaults.data(forKey: StorageKey.meetings),
       let storedMeetings = try? JSONDecoder().decode([Meeting].self, from: meetingData) {
      meetings = storedMeetings
    } else {
      meetings = sample.meetings
    }
    if let spaceData = defaults.data(forKey: StorageKey.spaces),
       let storedSpaces = try? JSONDecoder().decode([MemoraSpace].self, from: spaceData) {
      spaces = storedSpaces
    } else {
      spaces = sample.spaces
    }
    if let lifeLogData = defaults.data(forKey: StorageKey.lifeLogEntries),
       let storedEntries = try? JSONDecoder().decode([LifeLogEntry].self, from: lifeLogData) {
      lifeLogEntries = storedEntries
    } else {
      lifeLogEntries = SampleContent.makeLifeLog()
    }
    if let taskData = defaults.data(forKey: StorageKey.tasks),
       let storedTasks = try? JSONDecoder().decode([MemoraTask].self, from: taskData) {
      tasks = storedTasks
    } else {
      tasks = sample.tasks
    }
    aiHistory = [
      AIConversationEntry(
        id: UUID(),
        question: "今週決まったことは？",
        answer: "録音開始の速さを最優先にし、会議データは既定で端末内に保存する方針です。",
        scopeLabel: "すべての会話",
        createdAt: Calendar.current.date(byAdding: .hour, value: -4, to: .now)!
      )
    ]
  }

  // MARK: - Onboarding and account

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
    persist(
      MemoraAccount(
        displayName: displayName ?? Self.placeholderName(for: provider, email: address),
        email: address,
        provider: provider,
        createdAt: account?.createdAt ?? .now
      )
    )
  }

  func signOut() {
    persist(nil)
  }

  func deleteAccount() {
    persist(nil)
    aiHistory = []
  }

  /// Purchases are tied to the Apple ID, so Plus does not require a Memora
  /// account. Signing in only adds sync.
  func startSubscription() {
    isSubscribed = true
    UserDefaults.standard.set(true, forKey: StorageKey.isSubscribed)
  }

  /// Offers Plus once, and only after someone has seen a conversation get
  /// organized, so the value is visible before the price is.
  private func offerPlusIfNeeded() {
    guard !hasOfferedPlus, !isSubscribed else { return }
    hasOfferedPlus = true
    UserDefaults.standard.set(true, forKey: StorageKey.hasOfferedPlus)
    isPaywallPresented = true
  }

  private func persist(_ account: MemoraAccount?) {
    self.account = account
    let defaults = UserDefaults.standard
    if let account, let data = try? JSONEncoder().encode(account) {
      defaults.set(data, forKey: StorageKey.account)
    } else {
      defaults.removeObject(forKey: StorageKey.account)
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
    meetings.first { $0.id == id }
  }

  func space(id: UUID) -> MemoraSpace? {
    spaces.first { $0.id == id }
  }

  func startCapture() async {
    guard !isRecording else {
      isCapturePresented = true
      return
    }

    let allowed = await recorder.requestPermission()
    guard allowed else {
      microphonePermissionDenied = true
      return
    }

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
      startRecordingTicker()
      startLiveActivity()
    } catch {
      recordingErrorMessage = error.localizedDescription
    }
  }

  func stopCapture() async {
    guard isRecording else { return }
    recorder.stop()
    recordingTicker?.cancel()
    recordingTicker = nil
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
    guard let meetingID = pendingMeetingNavigationID else { return }
    pendingMeetingNavigationID = nil
    selectedTab = .files
    libraryPath = [.meeting(meetingID)]
  }

  func cancelCapture() async {
    recorder.stop()
    recordingTicker?.cancel()
    recordingTicker = nil
    isRecording = false
    isRecordingPaused = false
    isCapturePresented = false
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
      try? await Task.sleep(for: .milliseconds(850))
      guard !Task.isCancelled else { return }
      self?.updateMeeting(id) { $0.status = .transcribing(0.62) }
      try? await Task.sleep(for: .milliseconds(900))
      guard !Task.isCancelled else { return }
      self?.updateMeeting(id) { meeting in
        meeting.transcript = SampleContent.generatedTranscript
        meeting.status = .waitingForSummary
      }
    }
  }

  func generateSummary(_ id: UUID, template: SummaryTemplate, aiModel: SummaryAIModel) {
    guard let meeting = meeting(id: id), !meeting.transcript.isEmpty else { return }
    updateMeeting(id) { $0.status = .organizing("\(template.processingLabel) · \(aiModel.title)") }
    processingTasks[id]?.cancel()
    processingTasks[id] = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(1_100))
      guard !Task.isCancelled else { return }
      self?.finishProcessing(id)
    }
  }

  func toggleTask(_ id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[index].isCompleted.toggle()
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

    lifeLogEntries.insert(
      LifeLogEntry(
        id: UUID(),
        createdAt: createdAt,
        title: resolvedTitle,
        summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
        source: .iphone,
        meetingID: nil,
        kind: kind,
        photoData: photoData,
        eventDate: eventDate,
        locationName: trimmedLocation
      ),
      at: 0
    )
    persistLifeLog()
  }

  func saveAIExchange(question: String, answer: String, scopeLabel: String) {
    aiHistory.insert(
      AIConversationEntry(
        id: UUID(),
        question: question,
        answer: answer,
        scopeLabel: scopeLabel,
        createdAt: .now
      ),
      at: 0
    )
  }

  func renameMeeting(_ id: UUID, title: String) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    updateMeeting(id) { $0.title = trimmed }
  }

  func updateMeetingNotes(_ id: UUID, notes: String) {
    updateMeeting(id) { $0.notes = notes }
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

  func deleteMeeting(_ id: UUID) {
    meetings.removeAll { $0.id == id }
    persistMeetings()
    tasks.removeAll { $0.meetingID == id }
    persistTasks()
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
    aiHistory = []
    libraryPath = []
    selectedTab = .files
  }

  func removeAllContent() {
    meetings = []
    lifeLogEntries = []
    persistLifeLog()
    tasks = []
    persistTasks()
    aiHistory = []
    spaces = []
    persistMeetings()
    persistSpaces()
    libraryPath = []
  }

  func handle(_ url: URL) async {
    guard url.scheme == "memora" else { return }
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

  private func beginProcessing(_ id: UUID) {
    processingTasks[id]?.cancel()
    processingTasks[id] = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(900))
      guard !Task.isCancelled else { return }
      self?.updateMeeting(id) { $0.status = .transcribing(0.58) }

      try? await Task.sleep(for: .milliseconds(900))
      guard !Task.isCancelled else { return }
      self?.updateMeeting(id) { meeting in
        meeting.status = .organizing("決定と次の行動を整理中")
        meeting.transcript = SampleContent.generatedTranscript
      }

      try? await Task.sleep(for: .milliseconds(1_100))
      guard !Task.isCancelled else { return }
      self?.finishProcessing(id)
    }
  }

  private func finishProcessing(_ id: UUID) {
    updateMeeting(id) { meeting in
      meeting.title = meeting.title == "新しい会話" ? "プロダクト方針の確認" : meeting.title
      meeting.status = .ready
      meeting.summary = "次期リリースは、録音開始の速さと会議後の行動につながる体験を優先する方針で合意しました。"
      meeting.keyPoints = [
        "初回体験は説明よりも実際の録音を優先する",
        "AIの詳細設定は必要になった時だけ見せる"
      ]
      meeting.decisions = [
        "次期リリースでは録音とタスク抽出を最優先にする",
        "会議データは既定で端末内に保存する"
      ]
      meeting.openQuestions = [
        "クラウド同期を有料プランのどの段階で提供するか"
      ]
      meeting.transcript = SampleContent.generatedTranscript
    }

    let task = MemoraTask(
      id: UUID(),
      title: "初回録音フローの仕様を確定する",
      meetingID: id,
      assignee: "自分",
      dueDate: Calendar.current.date(byAdding: .day, value: 3, to: .now),
      isCompleted: false
    )
    tasks.insert(task, at: 0)
    persistTasks()
    offerPlusIfNeeded()
  }

  private func updateMeeting(_ id: UUID, change: (inout Meeting) -> Void) {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
    change(&meetings[index])
    persistMeetings()
  }

  private func persistTasks() {
    guard let data = try? JSONEncoder().encode(tasks) else { return }
    UserDefaults.standard.set(data, forKey: StorageKey.tasks)
  }

  private func persistLifeLog() {
    guard let data = try? JSONEncoder().encode(lifeLogEntries) else { return }
    UserDefaults.standard.set(data, forKey: StorageKey.lifeLogEntries)
  }

  private func persistMeetings() {
    guard let data = try? JSONEncoder().encode(meetings) else { return }
    UserDefaults.standard.set(data, forKey: StorageKey.meetings)
  }

  private func persistSpaces() {
    guard let data = try? JSONEncoder().encode(spaces) else { return }
    UserDefaults.standard.set(data, forKey: StorageKey.spaces)
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
