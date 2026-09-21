import ActivityKit
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class MemoraModel {
  var selectedTab = RootTab.home
  var homePath: [LibraryRoute] = []
  var libraryPath: [LibraryRoute] = []
  var fileSection = FileSection.meetingFiles
  var isFileCreationPresented = false
  var isSettingsPresented = false
  /// Shown when a `memora://` link points at a record this device does not
  /// have. It says what the link is and how to get the record back.
  var missingRecordNotice: MissingRecordNotice?
  var isRecentlyDeletedPresented = false

  /// Screens that asked for the bottom bar to step aside. The bar hides only
  /// when the screen being read is one of them, so a background screen cannot
  /// move the bar out from under the screen someone is actually using.
  var bottomBarHiddenScreens: Set<String> = []

  func isBottomBarHidden(for screenID: String) -> Bool {
    bottomBarHiddenScreens.contains(screenID)
  }

  func setBottomBarHidden(_ hidden: Bool, for screenID: String) {
    if hidden {
      bottomBarHiddenScreens.insert(screenID)
    } else {
      bottomBarHiddenScreens.remove(screenID)
    }
  }
  /// Records stay on the device unless Plus turns cloud storage on.
  var cloudStorageEnabled = false {
    didSet { UserDefaults.standard.set(cloudStorageEnabled, forKey: StorageKey.cloudStorage) }
  }
  var meetings: [Meeting] {
    didSet {
      meetingIndex.invalidate()
      // Only entries for records that are gone are dropped here; a record that
      // changed is invalidated at the update site, so one edit no longer throws
      // away every other record's cached search text.
      meetingSearchTexts = meetingSearchTexts.filter { id, _ in
        meetingIndex.element(id, in: meetings) != nil
      }
      rebuildMeetingAggregates()
    }
  }
  var spaces: [MemoraSpace] {
    didSet { spaceIndex.invalidate() }
  }
  var tasks: [MemoraTask] {
    didSet { tasksByMeeting = nil }
  }
  var lifeLogEntries: [LifeLogEntry] {
    didSet {
      newestEntries = nil
      rebuildLifeLogDays()
    }
  }
  /// Journal days newest first, with each day's records newest first. Built when
  /// the records change, so redraws reuse it.
  private(set) var lifeLogDays: [LifeLogDayGroup] = []
  /// Days that hold at least one record, for the calendar's dot.
  private(set) var markedLifeLogDays: Set<Date> = []
  /// Per-project counts and previews, and per-person record counts.
  private(set) var spaceAggregates: [UUID: SpaceAggregate] = [:]
  private(set) var personMeetingCounts: [UUID: Int] = [:]
  /// Records tagged with each person, newest first.
  private(set) var meetingsByPerson: [UUID: [Meeting]] = [:]
  var aiHistory: [AIConversationEntry]
  /// People who can be tagged on recordings.
  var people: [Person] = [] {
    didSet { personIndex.invalidate() }
  }
  /// Positions for the array lookups the screens do constantly.
  @ObservationIgnored private var meetingIndex = IdentifiableIndex<Meeting>()
  @ObservationIgnored private var meetingSearchTexts: [UUID: String] = [:]
  @ObservationIgnored private var dayChangeObservers: [NSObjectProtocol] = []
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
  /// The calendar event the recording in progress was started from. Cleared
  /// as soon as the record is saved or discarded, so only that record keeps
  /// the link and no later recording is attached to the wrong event.
  private(set) var captureEvent: UpcomingMeeting?
  /// True while a recording is being finished and stored.
  private(set) var isSavingCapture = false
  var recordingElapsed: TimeInterval = 0
  /// Smoothed 0...1 loudness for the recording glow.
  /// The glow's microphone level, kept in its own observable object so the ~22
  /// updates a second redraw only the view drawing the glow.
  @ObservationIgnored let levelMeter = RecordingLevelMeter()
  var recordingTitle = ""
  var recordingNote = ""
  var recordingErrorMessage: String?
  /// Explains why a recording paused itself (a call, a lost input), so the
  /// screen matches what actually happened.
  var recordingInterruptionMessage: String?
  var microphonePermissionDenied = false
  var isImporting = false
  /// Shown as indeterminate while the copy cannot be measured.
  var importProgress: Double?
  /// The floating controls' measured height. The shell is full-bleed, so the
  /// tab contents do not receive it as a safe-area inset and ask for it here.
  var bottomControlsHeight: CGFloat = 0
  /// Room a scroll view needs so its last item clears the floating controls.
  var bottomContentClearance: CGFloat {
    max(bottomControlsHeight, 24) + 16
  }
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
  /// What is typed in the composer. It lives here, not in the view, so it
  /// survives the composer being rebuilt, and in the draft store so it survives
  /// the app being stopped.
  var composerDraft = "" {
    didSet {
      guard composerDraft != oldValue else { return }
      scheduleComposerDraftSave()
    }
  }
  @ObservationIgnored private var composerDraftSaveTask: Task<Void, Never>?
  private static let composerDraftKey = "composer.question"
  /// True when the store could not be read at startup. Persisting is refused
  /// while it is set, so unreadable existing data is never written over.
  @ObservationIgnored private var isStoreProtected = false
  /// The engine Ask AI and summaries actually use. The model owns it, so what
  /// the composer shows and what the request calls cannot drift apart.
  var aiEngine: AIEngine = .automatic {
    didSet {
      UserDefaults.standard.set(aiEngine.rawValue, forKey: StorageKey.aiEngine)
    }
  }
  /// The bring-your-own-key provider used when the engine is cloud.
  var aiProvider: CloudProvider = .openAI {
    didSet {
      UserDefaults.standard.set(aiProvider.rawValue, forKey: StorageKey.aiProvider)
    }
  }
  /// The request currently being answered, so a newer one can drop it.
  @ObservationIgnored var aiChatRequestID: UUID?
  @ObservationIgnored var aiChatTask: Task<Void, Never>?

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
  /// Transcription and summary jobs, with the rules that decide whether a
  /// result still applies.
  @ObservationIgnored let processing = ProcessingService()
  /// Timings for the paths that matter when comparing builds. Holds numbers and
  /// names only, never content.
  @ObservationIgnored let performance = PerformanceLog.shared
  /// What a recording in progress would need to be recovered after a stop.
  @ObservationIgnored private var recordingDraft: RecordingDraft?
  @ObservationIgnored private var recordingActivity: Activity<MemoraRecordingAttributes>?
  @ObservationIgnored private var pendingMeetingNavigationID: UUID?
  @ObservationIgnored private let recorder = AudioRecorderService()

  init() {
    let defaults = UserDefaults.standard
    RecordStore.prepare()
    performance.loadStored()
    let launchStartedAt = Date()

    hasCompletedOnboarding = defaults.bool(forKey: StorageKey.hasCompletedOnboarding)
    isSubscribed = defaults.bool(forKey: StorageKey.isSubscribed)
    hasOfferedPlus = defaults.bool(forKey: StorageKey.hasOfferedPlus)
    aiEngine = AIEngine(rawValue: defaults.string(forKey: StorageKey.aiEngine) ?? "") ?? .automatic
    aiProvider = CloudProvider(rawValue: defaults.string(forKey: StorageKey.aiProvider) ?? "") ?? .openAI
    composerDraft = DraftStore.load(Self.composerDraftKey) ?? ""
    // Cloud storage is a paid option: without Plus the records stay on device.
    cloudStorageEnabled = defaults.bool(forKey: StorageKey.isSubscribed)
      && defaults.bool(forKey: StorageKey.cloudStorage)
    if case .data(let data) = RecordStore.load(StorageKey.account) {
      account = try? JSONDecoder().decode(MemoraAccount.self, from: data)
    }

    let sample = SampleContent.make()

    /// Reads a document from the local store, moving any legacy `UserDefaults`
    /// copy across exactly once. The three outcomes are kept apart: absent means
    /// a first run; unreadable means the bytes are set aside and the app says so;
    /// a store failure means the data is left untouched and nothing is written
    /// over it.
    func load<T: Decodable>(_ type: [T].Type, forKey key: String, fallback: [T]) -> [T] {
      switch RecordStore.load(key) {
      case .absent:
        return fallback
      case .failed:
        didFailToReadStore = true
        return []
      case .data(let data):
        if let stored = try? JSONDecoder().decode([T].self, from: data) {
          return stored
        }
        // The bytes are only removed once the copy beside them is safely stored.
        if RecordStore.quarantine(data, key: key) {
          didFindUnreadableData = true
        } else {
          didFailToReadStore = true
        }
        return []
      }
    }

    var didFindUnreadableData = false
    var didFailToReadStore = false

    meetings = load([Meeting].self, forKey: StorageKey.meetings, fallback: sample.meetings)
    spaces = load([MemoraSpace].self, forKey: StorageKey.spaces, fallback: sample.spaces)
    lifeLogEntries = load(
      [LifeLogEntry].self,
      forKey: StorageKey.lifeLogEntries,
      fallback: SampleContent.makeLifeLog()
    )
    tasks = load([MemoraTask].self, forKey: StorageKey.tasks, fallback: sample.tasks)
    people = load([Person].self, forKey: StorageKey.people, fallback: SampleContent.makePeople())
    let activeJobIDs = load([String].self, forKey: StorageKey.activeJobs, fallback: [])
    processing.restoreInterrupted(activeJobIDs)
    trashedRecords = load([TrashedRecord].self, forKey: StorageKey.trash, fallback: [])
    trashedLifeLogEntries = load(
      [TrashedLifeLogEntry].self,
      forKey: StorageKey.lifeLogTrash,
      fallback: []
    )
    if case .data(let draftData) = RecordStore.load(StorageKey.recordingDraft) {
      recordingDraft = try? JSONDecoder().decode(RecordingDraft.self, from: draftData)
      // A draft from an older build has no id; give it a stable one now so a
      // recovery that is cut off and retried does not make a second record.
      if recordingDraft?.id == nil {
        recordingDraft?.id = UUID()
      }
    }

    isStoreProtected = didFailToReadStore

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

    if didFailToReadStore {
      loadFailureMessage = "保存データを読み込めませんでした。データを壊さないため、この起動では保存を停止しています。アプリを再起動してください。"
    } else if didFindUnreadableData {
      loadFailureMessage = "保存されたデータの一部を読み込めませんでした。元のデータは端末に退避しています。"
    } else {
      loadFailureMessage = nil
    }

    // Saved transcripts are never rewritten at startup. A transcript recorded
    // by an older build cannot be told apart from real short utterances, so any
    // tidy-up would be a guess over the person's own words.

    // Anything that was mid-processing when the app stopped is offered for
    // retry instead of looking stuck forever.
    recoverInterruptedJobs()

    // Records kept past their recovery window are removed for good.
    purgeExpiredTrash()

    // A recording that was cut off by a stop is recovered as its own record,
    // never re-recorded.
    Task { await recoverRecordingDraft() }

    // Nothing is recording at launch, so no Live Activity should still be up.
    Task { await endStaleLiveActivities() }

    // Calls, route changes, and audio resets pause the recording instead of
    // silently losing it.
    recorder.onInterruption = { [weak self] event in
      self?.handleRecorderInterruption(event)
    }

    // didSet does not run for the loads above, so the derived data is built here.
    rebuildMeetingAggregates()
    rebuildLifeLogDays()

    // A finished job clears its flag, and the flag is what the next launch
    // reads to decide whether a job was interrupted.
    processing.onActiveIDsChanged = { [weak self] in
      self?.persistInterruptedJobs()
    }

    // How long the app needs before the first screen can be drawn, recorded
    // without any of the content that was loaded.
    performance.record(
      "起動（準備完了まで）",
      milliseconds: Date.now.timeIntervalSince(launchStartedAt) * 1_000,
      count: meetings.count
    )

    // A day or time zone change moves records between journal days.
    let dayChange: @Sendable (Notification) -> Void = { [weak self] _ in
      Task { @MainActor in self?.rebuildLifeLogDays() }
    }
    dayChangeObservers = [
      NotificationCenter.default.addObserver(
        forName: .NSCalendarDayChanged, object: nil, queue: .main, using: dayChange
      ),
      NotificationCenter.default.addObserver(
        forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: dayChange
      ),
      NotificationCenter.default.addObserver(
        forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main, using: dayChange
      )
    ]
  }

  /// One pass over the records for the per-project and per-person numbers the
  /// screens show, instead of a scan per tile per redraw.
  private func rebuildMeetingAggregates() {
    var personCounts: [UUID: Int] = [:]
    var bySpace: [UUID: [Meeting]] = [:]

    for meeting in meetings {
      if let spaceID = meeting.spaceID {
        bySpace[spaceID, default: []].append(meeting)
      }
      for personID in meeting.participantIDs ?? [] {
        personCounts[personID, default: 0] += 1
      }
    }

    spaceAggregates = bySpace.mapValues { group in
      let newest = group.sorted { $0.createdAt > $1.createdAt }
      return SpaceAggregate(
        meetingCount: group.count,
        icons: newest.prefix(4).map { $0.source == .recording ? "waveform" : "square.and.arrow.down" },
        latestDate: newest.first?.createdAt
      )
    }
    personMeetingCounts = personCounts

    var byPerson: [UUID: [Meeting]] = [:]
    for meeting in meetings {
      for personID in meeting.participantIDs ?? [] {
        byPerson[personID, default: []].append(meeting)
      }
    }
    meetingsByPerson = byPerson.mapValues { $0.sorted { $0.createdAt > $1.createdAt } }
  }

  /// Groups the journal by day once, newest first.
  private func rebuildLifeLogDays() {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: lifeLogEntries) { calendar.startOfDay(for: $0.createdAt) }
    lifeLogDays = grouped
      .map { LifeLogDayGroup(day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
      .sorted { $0.day > $1.day }
    markedLifeLogDays = Set(grouped.keys)
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
    let ids = Set(processing.activeIDStrings.compactMap(UUID.init(uuidString:)))
    guard !ids.isEmpty else { return }
    processing.restoreInterrupted([])
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

  private func persistInterruptedJobs() {
    persistInBackground(processing.activeIDStrings, forKey: StorageKey.activeJobs)
  }

  // MARK: - Recording recovery

  /// The minimum needed to bring back a recording the app did not get to save.
  /// The id identifies the record this recording will become, so an interrupted
  /// recovery that is tried again finds the record it already made instead of
  /// making a second one. Drafts written before the id was stored have none, and
  /// are given one on the first load.
  private struct RecordingDraft: Codable {
    var id: UUID?
    var fileName: String
    var title: String
    var note: String
    var startedAt: Date
  }

  /// Writes what a running recording would need if the app stopped now.
  private func persistRecordingDraft() {
    guard let recordingDraft else {
      try? RecordStore.remove(StorageKey.recordingDraft)
      return
    }
    persistInBackground(recordingDraft, forKey: StorageKey.recordingDraft)
  }

  /// Brings back a recording that was interrupted: its audio becomes a record
  /// awaiting transcription, or, when no audio survived, the note becomes a
  /// memo. Recording is never restarted on its own.
  private func recoverRecordingDraft() async {
    guard let draft = recordingDraft else { return }
    // A store that could not be read must not be written over, so recovery waits
    // for the next healthy launch instead of adding records that cannot be saved.
    guard !isStoreProtected else { return }

    let id = draft.id ?? UUID()
    // A recovery that already stored the record but was cut off before the draft
    // was removed must not make a second one.
    if meetings.contains(where: { $0.id == id }) || lifeLogEntries.contains(where: { $0.id == id }) {
      clearRecordingDraft()
      return
    }

    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let audioURL = MediaFiles.resolve(draft.fileName),
          FileManager.default.fileExists(atPath: audioURL.path) else {
      // With no audio, the note becomes a memo. The memo and the draft removal
      // are one commit, so a stop in the middle leaves one or the other. When
      // there is nothing worth keeping, the draft is simply removed.
      if note.isEmpty {
        clearRecordingDraft()
      } else if addLifeLogEntry(
        id: id,
        kind: .memo,
        title: title.isEmpty ? "復旧したメモ" : title,
        summary: note,
        createdAt: draft.startedAt,
        photoData: nil,
        eventDate: nil,
        locationName: nil,
        removingDraft: StorageKey.recordingDraft
      ) {
        clearRecordingDraft(alreadyRemoved: true)
      }
      return
    }

    let duration = await MediaFiles.duration(of: audioURL) ?? 1
    var meeting = Meeting(
      id: id,
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

    lifeLogEntries.insert(
      LifeLogEntry(
        id: id,
        createdAt: draft.startedAt,
        title: meeting.title,
        summary: "中断前に録音していた音声を復旧しました。",
        source: .iphone,
        meetingID: meeting.id
      ),
      at: 0
    )

    // The recovered record, its journal entry and the draft removal are written
    // together, so a stop in the middle leaves either all of it or none of it.
    let stored = await persistBatchAsync({
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(meetings)),
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(lifeLogEntries))
      ]
    }, removing: [StorageKey.recordingDraft])
    guard stored else {
      // Put the in-memory lists back so nothing points at a record that was not
      // written, and keep the draft for the next attempt.
      meetings.removeAll { $0.id == id }
      lifeLogEntries.removeAll { $0.id == id }
      return
    }
    recordingDraft = nil
  }

  /// Forgets the recording draft and removes its stored copy. `alreadyRemoved`
  /// says a commit has just removed it, so no second removal is needed.
  private func clearRecordingDraft(alreadyRemoved: Bool = false) {
    recordingDraft = nil
    if !alreadyRemoved {
      persistRecordingDraft()
    }
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
    if let account, persistNow(account, forKey: StorageKey.account) {
      // The legacy copy is only cleared once the store has it.
      UserDefaults.standard.removeObject(forKey: StorageKey.account)
    } else if account == nil {
      try? RecordStore.remove(StorageKey.account)
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
    let text = MemoraModel.searchableText(of: meeting)
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

  func startCapture(event: UpcomingMeeting? = nil) async {
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
      announce("マイクの使用が許可されていません。設定から許可してください。")
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
      captureEvent = event
      recordingTitle = event?.title ?? ""
      recordingNote = ""
      isRecordingPaused = false
      isRecording = true
      isCapturePresented = true
      levelMeter.reset()
      startRecordingTicker()
      startLevelTicker()
      startLiveActivity()
      announce("録音を開始しました")
      if let recordingURL, let fileName = MediaFiles.reference(for: recordingURL) {
        recordingDraft = RecordingDraft(
          id: UUID(),
          fileName: fileName,
          title: event?.title ?? "",
          note: "",
          startedAt: .now
        )
        persistRecordingDraft()
      }
    } catch {
      recordingErrorMessage = error.localizedDescription
    }
  }

  func stopCapture() async {
    guard isRecording, !isSavingCapture else { return }
    isSavingCapture = true
    let startedAt = Date()
    defer {
      isSavingCapture = false
      performance.record(
        "保存（録音の確定）",
        milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000
      )
    }

    recorder.stop()
    recordingTicker?.cancel()
    recordingTicker = nil
    levelTicker?.cancel()
    levelTicker = nil
    levelMeter.reset()
    isRecording = false
    isRecordingPaused = false
    await endLiveActivity()

    var meeting = Meeting(
      id: recordingDraft?.id ?? UUID(),
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
    meeting.calendarEventID = captureEvent?.id
    captureEvent = nil
    meetings.insert(meeting, at: 0)
    lifeLogEntries.insert(
      LifeLogEntry(
        id: meeting.id,
        createdAt: meeting.createdAt,
        title: meeting.title,
        summary: "iPhoneで新しい音声を記録しました。",
        source: .iphone,
        meetingID: meeting.id
      ),
      at: 0
    )
    // The record, its journal entry and the draft removal are one commit: the
    // draft is only gone once the record is stored, so a failure or a stop here
    // leaves the audio recoverable rather than lost. On failure the draft stays
    // and the next launch rebuilds the record from it (with the same id), so no
    // duplicate is made.
    let committed = await persistBatchAsync({
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(meetings)),
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(lifeLogEntries))
      ]
    }, removing: [StorageKey.recordingDraft])
    if committed {
      recordingDraft = nil
    }
    recordingInterruptionMessage = nil
    recordingURL = nil
    recordingStartedAt = nil
    recordingPausedAt = nil
    recordingPausedDuration = 0
    recordingTitle = ""
    recordingNote = ""
    captureEvent = nil
    selectedTab = .files
    fileSection = .meetingFiles
    pendingMeetingNavigationID = meeting.id
    isCapturePresented = false
    beginProcessing(meeting.id)
    announce("録音を保存しました。文字起こしを準備しています。")
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
    levelMeter.reset()
    isRecording = false
    isRecordingPaused = false
    isCapturePresented = false
    // Discarding means the audio goes too; nothing is kept for the journal.
    captureEvent = nil
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

  /// Copies an audio file into the app, checks that it can actually be played,
  /// and records its real length. The file work runs off the main actor, and a
  /// failed import leaves nothing behind.
  func importAudio(from sourceURL: URL) async {
    guard !isImporting else { return }
    isImporting = true
    importProgress = nil
    importErrorMessage = nil

    let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if hasSecurityScope {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    let fileExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
    let outcome = await Task.detached(priority: .userInitiated) { () -> ImportOutcome in
      let directory = MediaFiles.directory
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Work under a temporary name so a failure cannot leave a half file.
        let working = directory.appendingPathComponent("importing-\(UUID().uuidString).\(fileExtension)")
        try FileManager.default.copyItem(at: sourceURL, to: working)

        guard let duration = await MediaFiles.duration(of: working) else {
          try? FileManager.default.removeItem(at: working)
          return .unreadable
        }

        let destination = directory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: working, to: destination)
        return .imported(destination, duration)
      } catch {
        return .failed
      }
    }.value

    let title = sourceURL.deletingPathExtension().lastPathComponent
    switch outcome {
    case .imported(let destination, let duration):
      let meeting = Meeting(
        id: UUID(),
        title: title.isEmpty ? "インポートした音声" : title,
        createdAt: .now,
        duration: duration,
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
      isImporting = false
      selectedTab = .files
      fileSection = .meetingFiles
      libraryPath = [.meeting(meeting.id)]
    case .unreadable:
      isImporting = false
      importErrorMessage = "この音声は再生できないため取り込めませんでした。別のファイルをお試しください。"
    case .failed:
      isImporting = false
      importErrorMessage = "音声を読み込めませんでした。ファイル形式と空き容量を確認してください。"
    }
  }

  private enum ImportOutcome {
    case imported(URL, TimeInterval)
    case unreadable
    case failed
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

  /// Starts transcription for any record that has audio and is not already being
  /// processed: an imported file and a recovered recording take the same path.
  func startTranscription(_ id: UUID) {
    guard let meeting = meeting(id: id),
          meeting.audioURL != nil,
          !processing.isActive(id) else { return }
    updateMeeting(id) { $0.status = .transcribing(0.08) }
    processing.run(id: id) { [weak self] in
      guard let self else { return TranscriptionOutcome.unavailable }
      let availability = await EngineAvailability.transcription(
        EngineAvailability.currentTranscriptionEngine(),
        language: EngineAvailability.currentTranscriptionLanguage(),
        provider: EngineAvailability.currentTranscriptionProvider()
      )
      guard availability.isReady else {
        return .failed(availability.message ?? "文字起こしを開始できませんでした。")
      }
      try? await Task.sleep(for: .milliseconds(600))
      guard !Task.isCancelled else { return .unavailable }
      self.updateMeeting(id) { $0.status = .transcribing(0.62) }
      return await TranscriptionService.transcribe(fileURL: self.meeting(id: id)?.audioURL)
    } apply: { [weak self] outcome in
      guard let self, !Task.isCancelled else { return }
      switch outcome {
      case .segments(let segments):
        self.updateMeeting(id) { meeting in
          meeting.transcript = segments
          meeting.status = .waitingForSummary
        }
        self.announce("文字起こしができました。要約を作成しています。")
      case .unavailable:
        self.updateMeeting(id) {
          $0.status = .failed("この端末では文字起こしを利用できません。音声は保存されています。設定で別のエンジンを選ぶか、別の端末でお試しください。")
        }
        self.announce("文字起こしができませんでした。音声は保存されています。")
      case .failed(let message):
        self.updateMeeting(id) { $0.status = .failed(message) }
        self.announce("文字起こしができませんでした。\(message)")
      case .nothingRecognized:
        self.updateMeeting(id) {
          $0.status = .failed("音声から発言を認識できませんでした。音声は保存されています。もう一度お試しください。")
        }
        self.announce("音声から発言を認識できませんでした。")
      case .cancelled:
        // Nothing was applied: the record goes back to where it can be started
        // again, rather than being left looking stuck.
        self.updateMeeting(id) { meeting in
          if case .transcribing = meeting.status {
            meeting.status = .waitingForTranscription
          }
        }

      }
    }
  }

  /// Rewrites the summary from the real transcript with the chosen template.
  /// Nothing is invented: when no engine can answer, the record says so and
  /// keeps whatever the person had, rather than filling in sample text.
  func generateSummary(_ id: UUID, choice: SummaryTemplateChoice) {
    guard let meeting = meeting(id: id), !meeting.transcript.isEmpty else { return }

    updateMeeting(id) { $0.status = .organizing(choice.processingLabel) }
    let inputRevision = ProcessingService.inputRevision(meeting.transcript)
    let summaryRevision = meeting.summary
    let startedAt = Date()

    processing.run(id: id) { [weak self] in
      guard let self else { return AIAnswerResult.failure(.noEngine) }
      let transcript = meeting.transcript
        .map { "\($0.speaker): \($0.text)" }
        .joined(separator: "\n")
      return await AIEngineService.answer(
        engine: self.aiEngine,
        provider: self.aiProvider,
        question: choice.summaryInstruction,
        scopeLabel: "文字起こし",
        context: transcript,
        history: ""
      )
    } apply: { [weak self] result in
      guard let self, !Task.isCancelled else { return }
      self.performance.record(
        "処理（要約）",
        milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000
      )

      // The service checks the run; these two fingerprints catch an edit made
      // while the answer was being written. A transcript that changed or a
      // summary that was edited by hand wins over the older result.
      guard let current = self.meeting(id: id) else { return }
      let transcriptChanged = ProcessingService.inputRevision(current.transcript) != inputRevision
      let summaryEdited = current.summary != summaryRevision
      guard !transcriptChanged, !summaryEdited else {
        self.updateMeeting(id) { $0.status = .waitingForSummary }
        self.announce("記録が編集されたため、古い要約は反映しませんでした。もう一度生成できます。")
        return
      }

      if let resultFailure = result.failure, resultFailure == .cancelled {
        // Cancelled without a newer request taking over: leave the record able
        // to be generated again rather than stuck mid-process.
        self.updateMeeting(id) { meeting in
          if case .organizing = meeting.status {
            meeting.status = .waitingForSummary
          }
        }
        return
      }

      let summary = result.text?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let summary, !summary.isEmpty {
        self.updateMeeting(id) { meeting in
          meeting.summary = summary
          meeting.status = .ready
        }
        self.offerPlusIfNeeded()
        self.announce("文字起こしと要約ができました。")
      } else {
        let message = result.failure?.message
          ?? "要約が空でした。もう一度お試しください。"
        self.updateMeeting(id) { $0.status = .failed(message) }
        self.announce("要約を作成できませんでした。\(message)")
      }
    }
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

  @discardableResult
  func addLifeLogEntry(
    id: UUID = UUID(),
    kind: LifeLogKind,
    title: String,
    summary: String,
    createdAt: Date,
    photoData: Data?,
    eventDate: Date?,
    locationName: String?,
    removingDraft draftKey: String? = nil
  ) -> Bool {
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
    let photoFileName = photoData.flatMap { MediaFiles.writePhoto($0, thumbnailMaxSide: 400) }

    lifeLogEntries.insert(
      LifeLogEntry(
        id: id,
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
    // The entry and the draft removal land together when the caller asked for
    // one, so leaving the draft behind cannot happen beside a stored memo.
    return persistBatch({
      [(key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(lifeLogEntries))]
    }, removing: draftKey.map { [$0] } ?? [])
  }

  func renameMeeting(_ id: UUID, title: String) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    updateMeeting(id) { $0.title = trimmed }
  }

  /// Notes and summary come from an editor that keeps a draft; the caller is
  /// told whether the record was stored, and only then is the draft cleared.
  @discardableResult
  func updateMeetingNotes(_ id: UUID, notes: String) async -> Bool {
    await commitMeetingChange(id) { $0.notes = notes }
  }

  @discardableResult
  func updateMeetingSummary(_ id: UUID, summary: String) async -> Bool {
    await commitMeetingChange(id) { $0.summary = summary }
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
    meetingSearchTexts.removeValue(forKey: meetingID)
    persistMeetings()
  }

  /// Corrects the body of one transcript segment, leaving the speaker as is.
  func updateTranscriptSegment(meetingID: UUID, segmentID: UUID, text: String) {
    guard let meetingIndex = meetings.firstIndex(where: { $0.id == meetingID }),
          let segmentIndex = meetings[meetingIndex].transcript.firstIndex(where: { $0.id == segmentID }) else { return }
    meetings[meetingIndex].transcript[segmentIndex].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    meetingSearchTexts.removeValue(forKey: meetingID)
    persistMeetings()
  }

  /// Moves a record to the trash. Its audio, tasks, and journal entries are kept
  /// so it can be restored exactly, and removed only when the trash is emptied.
  func deleteMeeting(_ id: UUID) {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }

    processing.cancel(id)

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

    // One operation: the record, its tasks, its journal entries, and the trash
    // entry land together or not at all.
    persistBatch {
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(meetings)),
        (key: StorageKey.tasks, data: try RecordStore.encoded(tasks)),
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(lifeLogEntries)),
        (key: StorageKey.trash, data: try RecordStore.encoded(trashedRecords))
      ]
    }
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

    persistBatch {
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(meetings)),
        (key: StorageKey.tasks, data: try RecordStore.encoded(tasks)),
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(lifeLogEntries)),
        (key: StorageKey.trash, data: try RecordStore.encoded(trashedRecords))
      ]
    }
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

    // The whole package is checked before anything is touched.
    let manifest = try BackupPackage.read(from: packageURL)
    try BackupPackage.install(mediaFrom: packageURL, manifest: manifest)

    // The records go in as one write. If it fails, the media that was just put
    // in place is taken back, so the device is left as it was.
    let stored = persistBatch {
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(manifest.meetings)),
        (key: StorageKey.spaces, data: try RecordStore.encoded(manifest.spaces)),
        (key: StorageKey.tasks, data: try RecordStore.encoded(manifest.tasks)),
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(manifest.lifeLogEntries)),
        (key: StorageKey.people, data: try RecordStore.encoded(manifest.people)),
        (key: StorageKey.aiHistory, data: try RecordStore.encoded(manifest.aiHistory))
      ]
    }
    guard stored else {
      BackupPackage.removeInstalledMedia(manifest.audioFileNames, isAudio: true)
      BackupPackage.removeInstalledMedia(manifest.photoFileNames, isAudio: false)
      throw BackupPackage.BackupError.mediaInstallFailed(manifest.audioFileNames + manifest.photoFileNames)
    }

    meetings = manifest.meetings
    spaces = manifest.spaces
    tasks = manifest.tasks
    lifeLogEntries = manifest.lifeLogEntries
    people = manifest.people
    aiHistory = manifest.aiHistory
  }

  func addMeetingPhoto(_ id: UUID, data: Data) {
    guard let name = MediaFiles.writePhoto(data, thumbnailMaxSide: 400) else {
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
      guard let id = UUID(uuidString: url.lastPathComponent) else { return }
      // A link is to a record on this device; it resolves nowhere else, so a
      // missing record is explained instead of opening an empty screen.
      if meeting(id: id) != nil {
        selectedTab = .files
        fileSection = .meetingFiles
        libraryPath = [.meeting(id)]
      } else if trashedRecords.contains(where: { $0.meeting.id == id }) {
        missingRecordNotice = MissingRecordNotice(
          message: "この記録は「最近削除した項目」にあります。元に戻すか確認してください。",
          offersTrash: true
        )
      } else {
        missingRecordNotice = MissingRecordNotice(
          message: "この端末にこの記録はありません。リンクは記録のある端末でのみ開けます。バックアップから復元できる場合があります。",
          offersTrash: false
        )
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

  /// Drafts are written a moment after typing stops, so a keystroke does not
  /// wait on the store.
  private func scheduleComposerDraftSave() {
    composerDraftSaveTask?.cancel()
    composerDraftSaveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(600))
      guard let self, !Task.isCancelled else { return }
      if self.composerDraft.isEmpty {
        DraftStore.clear(Self.composerDraftKey)
      } else {
        DraftStore.save(self.composerDraft, key: Self.composerDraftKey)
      }
      self.composerDraftSaveTask = nil
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
        // Nothing shows the glow unless a screen asks for it, and recording
        // itself does not depend on the level being sampled.
        if self.levelMeter.isActive {
          self.levelMeter.update(from: self.isRecordingPaused ? 0 : self.recorder.level())
          try? await Task.sleep(for: .milliseconds(45))
        } else {
          try? await Task.sleep(for: .milliseconds(300))
        }
      }
    }
  }

  /// Tells VoiceOver about a change it cannot see, such as a recording that
  /// started or a transcript that finished.
  private func announce(_ message: String) {
    UIAccessibility.post(notification: .announcement, argument: message)
  }

  private func beginProcessing(_ id: UUID) {
    processing.run(id: id) { [weak self] in
      guard let self else { return TranscriptionOutcome.unavailable }
      // Checked before the job starts, so a missing key or an unsupported
      // language is reported at once instead of after a spinner.
      let availability = await EngineAvailability.transcription(
        EngineAvailability.currentTranscriptionEngine(),
        language: EngineAvailability.currentTranscriptionLanguage(),
        provider: EngineAvailability.currentTranscriptionProvider()
      )
      guard availability.isReady else {
        return .failed(availability.message ?? "文字起こしを開始できませんでした。")
      }
      let startedAt = Date()
      defer {
        self.performance.record(
          "処理（文字起こし）",
          milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000
        )
      }
      try? await Task.sleep(for: .milliseconds(700))
      guard !Task.isCancelled else { return .unavailable }
      self.updateMeeting(id) { $0.status = .transcribing(0.58) }

      // Only a real engine's transcript is ever stored. When none can run, the
      // record says so and keeps the audio for a retry — never sample text.
      return await TranscriptionService.transcribe(fileURL: self.meeting(id: id)?.audioURL)
    } apply: { [weak self] outcome in
      guard let self, !Task.isCancelled else { return }
      switch outcome {
      case .segments(let segments):
        self.updateMeeting(id) { meeting in
          meeting.transcript = segments
          meeting.status = .waitingForSummary
        }
        self.announce("文字起こしができました。要約を作成しています。")
      case .unavailable:
        self.updateMeeting(id) {
          $0.status = .failed("この端末では文字起こしを利用できません。音声は保存されています。設定で別のエンジンを選ぶか、別の端末でお試しください。")
        }
        self.announce("文字起こしができませんでした。音声は保存されています。")
      case .failed(let message):
        self.updateMeeting(id) { $0.status = .failed(message) }
        self.announce("文字起こしができませんでした。\(message)")
      case .nothingRecognized:
        self.updateMeeting(id) {
          $0.status = .failed("音声から発言を認識できませんでした。音声は保存されています。もう一度お試しください。")
        }
        self.announce("音声から発言を認識できませんでした。")
      case .cancelled:
        // Nothing was applied: the record goes back to where it can be started
        // again, rather than being left looking stuck.
        self.updateMeeting(id) { meeting in
          if case .transcribing = meeting.status {
            meeting.status = .waitingForTranscription
          }
        }

      }
    }
  }

  @discardableResult
  private func updateMeeting(_ id: UUID, change: (inout Meeting) -> Void) -> Bool {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return false }
    meetingSearchTexts.removeValue(forKey: id)
    change(&meetings[index])
    persistMeetings()
    return true
  }

  /// Applies an edit and waits for it to be stored, reporting whether it landed.
  /// Used where a draft is cleared afterwards, so the draft is kept when the
  /// record could not be written.
  @discardableResult
  private func commitMeetingChange(_ id: UUID, change: (inout Meeting) -> Void) async -> Bool {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return false }
    meetingSearchTexts.removeValue(forKey: id)
    change(&meetings[index])
    return await persistNowAsync(meetings, forKey: StorageKey.meetings)
  }

  func persistTasks() {
    persistInBackground(tasks, forKey: StorageKey.tasks)
  }

  private func persistLifeLog() {
    persistInBackground(lifeLogEntries, forKey: StorageKey.lifeLogEntries)
  }

#if DEBUG
  /// The prefix the synthetic records used for measurements carry, so they can
  /// be recognised and removed again.
  static let measurementTitlePrefix = "計測用レコード "

  /// Adds numbered records so launch, search, and save can be measured at the
  /// sizes the review asks about (100 / 1,000). They hold no audio, no summary,
  /// and no transcript — only a label and a date.
  func addMeasurementRecords(_ count: Int) {
    let existing = meetings.filter { $0.title.hasPrefix(Self.measurementTitlePrefix) }.count
    for offset in 0..<count {
      meetings.insert(
        Meeting(
          id: UUID(),
          title: "\(Self.measurementTitlePrefix)\(existing + offset + 1)",
          createdAt: .now.addingTimeInterval(-Double(offset) * 60),
          duration: 60,
          source: .importFile,
          status: .ready,
          summary: "",
          keyPoints: [],
          decisions: [],
          openQuestions: [],
          transcript: []
        ),
        at: 0
      )
    }
    persistMeetings()
  }

  func removeMeasurementRecords() {
    meetings.removeAll { $0.title.hasPrefix(Self.measurementTitlePrefix) }
    persistMeetings()
  }
#endif

  func persistMeetings() {
    let startedAt = Date()
    defer {
      performance.record(
        "保存（会議の引き渡し）",
        milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000,
        count: meetings.count
      )
    }
    persistInBackground(meetings, forKey: StorageKey.meetings)
  }

  private func persistSpaces() {
    persistInBackground(spaces, forKey: StorageKey.spaces)
  }

  private func persistInBackground<T: Encodable & Sendable>(_ value: T, forKey key: String) {
    // A store that could not be read must not be written over: the existing
    // records may still be there, and replacing them would lose them.
    guard !isStoreProtected else {
      persistenceFailureMessage = storeProtectedMessage
      return
    }
    RecordStore.save(value, key: key) { [weak self] in
      self?.persistenceFailureMessage = "データを保存できませんでした。ストレージの空き容量を確認してください。"
    }
  }

  /// Waits for the write and reports whether it worked, for operations that must
  /// know before doing anything else.
  @discardableResult
  private func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    guard !isStoreProtected else {
      persistenceFailureMessage = storeProtectedMessage
      return false
    }
    do {
      try RecordStore.saveNow(value, key: key)
      return true
    } catch {
      persistenceFailureMessage = "データを保存できませんでした。ストレージの空き容量を確認してください。"
      return false
    }
  }

  /// Waits for a write of several documents that belong to one operation, and
  /// reports whether all of them landed. `removing` lets the same commit discard
  /// the draft that belongs to the operation.
  @discardableResult
  private func persistBatch(
    _ build: () throws -> [(key: String, data: Data)],
    removing: [String] = []
  ) -> Bool {
    guard !isStoreProtected else {
      persistenceFailureMessage = storeProtectedMessage
      return false
    }
    do {
      try RecordStore.commitNow(writes: try build(), removing: removing)
      return true
    } catch {
      persistenceFailureMessage = saveFailureMessage
      return false
    }
  }

  /// The same commit, off the caller's turn, for a screen that must not wait on
  /// disk while it finishes.
  @discardableResult
  private func persistBatchAsync(
    _ build: () throws -> [(key: String, data: Data)],
    removing: [String] = []
  ) async -> Bool {
    guard !isStoreProtected else {
      persistenceFailureMessage = storeProtectedMessage
      return false
    }
    do {
      try await RecordStore.commitAsync(writes: try build(), removing: removing)
      return true
    } catch {
      persistenceFailureMessage = saveFailureMessage
      return false
    }
  }

  /// Stores one document and waits for it, without blocking the caller while the
  /// write is in flight.
  @discardableResult
  private func persistNowAsync<T: Encodable>(_ value: T, forKey key: String) async -> Bool {
    guard !isStoreProtected else {
      persistenceFailureMessage = storeProtectedMessage
      return false
    }
    do {
      let data = try RecordStore.encoded(value)
      try await RecordStore.commitAsync(writes: [(key: key, data: data)], removing: [])
      return true
    } catch {
      persistenceFailureMessage = saveFailureMessage
      return false
    }
  }

  private var saveFailureMessage: String {
    "データを保存できませんでした。ストレージの空き容量を確認してください。"
  }

  private var storeProtectedMessage: String {
    "保存データを読み込めなかったため、上書きを止めています。アプリを再起動してください。"
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
    static let aiProvider = "memora.aiProvider"
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

  /// Anchors the state to the real elapsed time, so the live timer matches the
  /// screen and a pause freezes the number instead of counting on.
  private func updateLiveActivity() {
    guard let recordingActivity else { return }
    let elapsed = recordingElapsed
    let state = MemoraRecordingAttributes.ContentState(
      startedAt: Date.now.addingTimeInterval(-elapsed),
      isPaused: isRecordingPaused,
      pausedElapsed: elapsed
    )
    let content = ActivityContent(state: state, staleDate: nil)
    Task {
      await recordingActivity.update(content)
    }
  }

  private func endLiveActivity() async {
    guard let recordingActivity else { return }
    let state = MemoraRecordingAttributes.ContentState(
      startedAt: recordingStartedAt ?? .now,
      isPaused: false,
      pausedElapsed: recordingElapsed
    )
    let content = ActivityContent(state: state, staleDate: nil)
    await recordingActivity.end(content, dismissalPolicy: .immediate)
    self.recordingActivity = nil
  }

  /// Ends any activity left over from a previous run. Recording never resumes on
  /// its own, so a stale one would only show the wrong thing.
  private func endStaleLiveActivities() async {
    for activity in Activity<MemoraRecordingAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
