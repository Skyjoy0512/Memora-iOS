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
  @ObservationIgnored private var meetingSearchTexts: [UUID: MeetingSearchText] = [:]
  @ObservationIgnored private var spaceIndex = IdentifiableIndex<MemoraSpace>()
  @ObservationIgnored private var personIndex = IdentifiableIndex<Person>()
  /// Tasks grouped by the meeting they belong to, built once per change.
  @ObservationIgnored private var tasksByMeeting: [UUID: [MemoraTask]]?
  /// The journal's records newest first, sorted once per change.
  @ObservationIgnored private var newestEntries: [LifeLogEntry]?
  /// Marketplace summary templates the person has added.
  private(set) var installedTemplateIDs: [String] = []
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
  var recordingElapsed: TimeInterval = 0
  /// Smoothed 0...1 loudness for the recording glow.
  var recordingLevel: Double = 0
  var recordingTitle = ""
  var recordingNote = ""
  var recordingErrorMessage: String?
  var microphonePermissionDenied = false
  var isImporting = false
  var importProgress = 0.0
  var importErrorMessage: String?
  /// Set when stored data exists but could not be read. The data is kept aside
  /// rather than overwritten with samples.
  private(set) var loadFailureMessage: String?
  /// Set when a media file that should have been removed could not be.
  var deletionFailureMessage: String?
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
  /// The engine the Ask AI composer asks with.
  var aiModel: AIModel = .standard {
    didSet {
      UserDefaults.standard.set(aiModel.rawValue, forKey: StorageKey.aiModel)
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
  @ObservationIgnored private var recordingActivity: Activity<MemoraRecordingAttributes>?
  @ObservationIgnored private var pendingMeetingNavigationID: UUID?
  @ObservationIgnored private let recorder = AudioRecorderService()

  init() {
    let defaults = UserDefaults.standard
    hasCompletedOnboarding = defaults.bool(forKey: StorageKey.hasCompletedOnboarding)
    isSubscribed = defaults.bool(forKey: StorageKey.isSubscribed)
    hasOfferedPlus = defaults.bool(forKey: StorageKey.hasOfferedPlus)
    aiModel = AIModel(rawValue: defaults.string(forKey: StorageKey.aiModel) ?? "") ?? .standard
    // Cloud storage is a paid option: without Plus the records stay on device.
    cloudStorageEnabled = defaults.bool(forKey: StorageKey.isSubscribed)
      && defaults.bool(forKey: StorageKey.cloudStorage)
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
    if let peopleData = defaults.data(forKey: StorageKey.people),
       let storedPeople = try? JSONDecoder().decode([Person].self, from: peopleData) {
      people = storedPeople
    } else {
      people = SampleContent.makePeople()
    }
    installedTemplateIDs = defaults.stringArray(forKey: StorageKey.installedTemplates) ?? []
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
    meetingIndex.element(id, in: meetings)
  }

  /// The text a meeting is matched against while searching. It is joined once
  /// and reused, so typing does not rebuild every transcript on each keystroke.
  /// `includingSections` adds the extracted decisions, as the Ask AI search does.
  func searchText(for meeting: Meeting, includingSections: Bool = false) -> String {
    if let cached = meetingSearchTexts[meeting.id] {
      return includingSections ? cached.extended : cached.core
    }

    let transcript = meeting.transcript.map(\.text)
    let core = ([meeting.title, meeting.summary] + transcript).joined(separator: "\n")
    let extended = ([meeting.title, meeting.summary] + meeting.decisions + transcript)
      .joined(separator: "\n")

    meetingSearchTexts[meeting.id] = MeetingSearchText(core: core, extended: extended)
    return includingSections ? extended : core
  }

  private struct MeetingSearchText {
    var core: String
    var extended: String
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
      recordingLevel = 0
      startRecordingTicker()
      startLevelTicker()
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
    levelTicker?.cancel()
    levelTicker = nil
    recordingLevel = 0
    isRecording = false
    isRecordingPaused = false
    isCapturePresented = false
    // Discarding means the audio goes too; nothing is kept for the journal.
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
      } else {
        self.updateMeeting(id) {
          $0.status = .failed("要約を生成できませんでした。AIエンジンとキーを確認して再試行してください。")
        }
      }

      self.processingTasks[id] = nil
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

  func deleteMeeting(_ id: UUID) {
    // Stop anything still being generated for this record, and drop its audio
    // once the record itself is gone.
    let audioURL = meeting(id: id)?.audioURL
    processingTasks[id]?.cancel()
    processingTasks[id] = nil
    processingRevisions[id] = nil

    meetings.removeAll { $0.id == id }
    persistMeetings()
    tasks.removeAll { $0.meetingID == id }
    persistTasks()
    lifeLogEntries.removeAll { $0.meetingID == id }
    persistLifeLog()

    if !MediaFiles.delete(audioURL) {
      deletionFailureMessage = "会議の音声ファイルを削除できませんでした。ストレージの空き容量を確認してください。"
    }
  }

  func addMeetingPhoto(_ id: UUID, data: Data) {
    updateMeeting(id) { meeting in
      var photos = meeting.photoData ?? []
      photos.append(data)
      meeting.photoData = photos
    }
  }

  func removeMeetingPhoto(_ id: UUID, index: Int) {
    updateMeeting(id) { meeting in
      var photos = meeting.photoData ?? []
      guard photos.indices.contains(index) else { return }
      photos.remove(at: index)
      meeting.photoData = photos.isEmpty ? nil : photos
    }
  }

  // MARK: - People

  func person(id: UUID) -> Person? {
    personIndex.element(id, in: people)
  }

  func persistPeople() {
    guard let data = try? JSONEncoder().encode(people) else { return }
    UserDefaults.standard.set(data, forKey: StorageKey.people)
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

  /// Encoding and writing run off the main thread, and in order, so a burst of
  /// edits does not stall the UI or leave an older snapshot behind.
  private let persistenceQueue = DispatchQueue(label: "app.memora.persistence", qos: .utility)

  private func persistInBackground<T: Encodable & Sendable>(_ value: T, forKey key: String) {
    persistenceQueue.async {
      guard let data = try? JSONEncoder().encode(value) else { return }
      UserDefaults.standard.set(data, forKey: key)
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
    static let aiModel = "memoraAIModel"
    static let people = "memoraPeople"
    static let installedTemplates = "memoraInstalledTemplates"
    static let cloudStorage = "memoraCloudStorage"
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
