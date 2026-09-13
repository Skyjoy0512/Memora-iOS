import ActivityKit
import Foundation
import Observation

@MainActor
@Observable
final class MemoraModel {
  var selectedTab = RootTab.records
  var libraryPath: [LibraryRoute] = []
  var meetings: [Meeting]
  var spaces: [MemoraSpace]
  var tasks: [MemoraTask]
  var aiHistory: [AIConversationEntry]
  var isCapturePresented = false
  var isCaptureSourcePresented = false
  var isRecording = false
  var recordingElapsed: TimeInterval = 0
  var recordingErrorMessage: String?
  var microphonePermissionDenied = false
  var isImporting = false
  var importProgress = 0.0
  var importErrorMessage: String?
  var account: MemoraAccount?
  var isAuthPresented = false
  var isPaywallPresented = false
  var omiPairingManager = OmiPairingManager()
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
    meetings = sample.meetings
    spaces = sample.spaces
    tasks = sample.tasks
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
      recordingElapsed = 0
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
    await endLiveActivity()

    let meeting = Meeting(
      id: UUID(),
      title: "新しい会話",
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
    meetings.insert(meeting, at: 0)
    recordingURL = nil
    recordingStartedAt = nil
    selectedTab = .records
    pendingMeetingNavigationID = meeting.id
    isCapturePresented = false
    beginProcessing(meeting.id)
  }

  func completeCaptureDismissal() {
    guard let meetingID = pendingMeetingNavigationID else { return }
    pendingMeetingNavigationID = nil
    selectedTab = .records
    libraryPath = [.meeting(meetingID)]
  }

  func cancelCapture() async {
    recorder.stop()
    recordingTicker?.cancel()
    recordingTicker = nil
    isRecording = false
    isCapturePresented = false
    recordingURL = nil
    recordingStartedAt = nil
    await endLiveActivity()
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
        status: .transcribing(0.1),
        summary: "音声を取り込みました。文字起こしを準備しています。",
        keyPoints: [],
        decisions: [],
        openQuestions: [],
        transcript: [],
        spaceID: nil,
        audioURL: destination
      )
      meetings.insert(meeting, at: 0)
      importProgress = 1
      try? await Task.sleep(for: .milliseconds(350))
      isImporting = false
      selectedTab = .records
      libraryPath = [.meeting(meeting.id)]
      beginProcessing(meeting.id)
    } catch {
      isImporting = false
      importErrorMessage = "音声を読み込めませんでした。ファイル形式と空き容量を確認してください。"
    }
  }

  func retryProcessing(_ id: UUID) {
    updateMeeting(id) { meeting in
      meeting.status = .transcribing(0.08)
    }
    beginProcessing(id)
  }

  func toggleTask(_ id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[index].isCompleted.toggle()
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

  func renameSpeaker(meetingID: UUID, segmentID: UUID, name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let meetingIndex = meetings.firstIndex(where: { $0.id == meetingID }),
          let segmentIndex = meetings[meetingIndex].transcript.firstIndex(where: { $0.id == segmentID }) else { return }
    meetings[meetingIndex].transcript[segmentIndex].speaker = trimmed
    meetings[meetingIndex].transcript[segmentIndex].speakerIsCertain = true
  }

  func deleteMeeting(_ id: UUID) {
    meetings.removeAll { $0.id == id }
    tasks.removeAll { $0.meetingID == id }
  }

  func resetSampleContent() {
    let sample = SampleContent.make()
    meetings = sample.meetings
    spaces = sample.spaces
    tasks = sample.tasks
    aiHistory = []
    libraryPath = []
    selectedTab = .records
  }

  func removeAllContent() {
    meetings = []
    tasks = []
    aiHistory = []
    spaces = []
    libraryPath = []
  }

  func handle(_ url: URL) async {
    guard url.scheme == "memora" else { return }
    selectedTab = .records
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
        self.recordingElapsed = Date.now.timeIntervalSince(startedAt)
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
    offerPlusIfNeeded()
  }

  private func updateMeeting(_ id: UUID, change: (inout Meeting) -> Void) {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
    change(&meetings[index])
  }

  private enum StorageKey {
    static let hasCompletedOnboarding = "hasSeenMemoraWelcome"
    static let hasOfferedPlus = "hasOfferedMemoraPlus"
    static let isSubscribed = "memoraPlusActive"
    static let account = "memoraAccount"
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

  private func endLiveActivity() async {
    guard let recordingActivity else { return }
    let startedAt = recordingStartedAt ?? .now
    let state = MemoraRecordingAttributes.ContentState(startedAt: startedAt, isPaused: false)
    let content = ActivityContent(state: state, staleDate: nil)
    await recordingActivity.end(content, dismissalPolicy: .immediate)
    self.recordingActivity = nil
  }
}
