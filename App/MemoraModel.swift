import ActivityKit
import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class MemoraModel {
  var selectedTab = RootTab.files
  var homePath: [LibraryRoute] = []
  var libraryPath: [LibraryRoute] = []
  var isFileCreationPresented = false
  var isSettingsPresented = false
  /// Opened by the contextual create button on the tasks tab.
  var isAddTaskPresented = false
  /// A task to open for editing after its reminder was tapped.
  var pendingTaskEditID: UUID?
  /// Opened by the contextual create button on the journal tab.
  var isLifeLogCreationPresented = false
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
      refreshSampleContentFlag()
    }
  }
  var spaces: [MemoraSpace] {
    didSet {
      spaceIndex.invalidate()
      refreshSampleContentFlag()
    }
  }
  /// Documents and slides made from the records, newest first.
  var documents: [MemoraDocument] = []
  var tasks: [MemoraTask] {
    didSet {
      tasksByMeeting = nil
      refreshSampleContentFlag()
    }
  }
  var lifeLogEntries: [LifeLogEntry] {
    didSet {
      newestEntries = nil
      rebuildLifeLogDays()
      refreshSampleContentFlag()
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
  /// Each record's title, for rows that only name their source record (a
  /// task's). Reading this instead of the record keeps those rows from
  /// redrawing whenever any record changes, such as a progress update.
  private(set) var meetingTitles: [UUID: String] = [:]
  var aiHistory: [AIConversationEntry]
  /// People who can be tagged on recordings.
  var people: [Person] = [] {
    didSet {
      personIndex.invalidate()
      refreshSampleContentFlag()
    }
  }
  /// Positions for the array lookups the screens do constantly.
  @ObservationIgnored private var meetingIndex = IdentifiableIndex<Meeting>()
  @ObservationIgnored var meetingSearchTexts: [UUID: String] = [:]
  @ObservationIgnored private var dayChangeObservers: [NSObjectProtocol] = []
  @ObservationIgnored private var inboxObserver: NSObjectProtocol?
  @ObservationIgnored private var taskReminderObserver: NSObjectProtocol?
  /// Audio files handed to the app while a recording owns the microphone.
  @ObservationIgnored var pendingImportURLs: [URL] = []
  /// Files being imported right now, so the Inbox scan never mistakes a file
  /// that is on its way in for one left behind.
  @ObservationIgnored var inFlightImportURLs: Set<URL> = []
  @ObservationIgnored private var spaceIndex = IdentifiableIndex<MemoraSpace>()
  @ObservationIgnored var personIndex = IdentifiableIndex<Person>()
  /// Tasks grouped by the meeting they belong to, built once per change.
  @ObservationIgnored private var tasksByMeeting: [UUID: [MemoraTask]]?
  /// The journal's records newest first, sorted once per change.
  @ObservationIgnored private var newestEntries: [LifeLogEntry]?
  /// Marketplace summary templates the person has added.
  var installedTemplateIDs: [String] = []
  /// Records that were deleted and can still be brought back.
  var trashedRecords: [TrashedRecord] = []
  /// Journal entries that were deleted and can still be brought back.
  var trashedLifeLogEntries: [TrashedLifeLogEntry] = []
  /// The Ask AI chat transcript.
  var aiMessages: [AIChatMessage] = []
  /// What new Ask AI questions look across.
  var aiScope: AIChatScope = .all
  /// Ask AI works as an agent: it uses tools to read records and, with the
  /// person's approval, make documents, tasks, projects and memos.
  var isAgentModeEnabled = UserDefaults.standard.bool(forKey: StorageKey.agentMode) {
    didSet { UserDefaults.standard.set(isAgentModeEnabled, forKey: StorageKey.agentMode) }
  }
  /// The change the agent is waiting for the person to approve or decline.
  var pendingAgentApproval: AgentApproval?
  /// An email the agent drafted, waiting to open in the composer.
  var pendingMailDraft: MailDraft?
  var isAIChatResponding = false
  var isCapturePresented = false
  var isCaptureSourcePresented = false
  /// True while a tab's search is open. The tab bar and Ask AI step aside so
  /// the search reads as its own screen.
  var isSearchActive = false
  var isOnlineMeetingCapturePresented = false
  var isRecording = false
  var isRecordingPaused = false
  /// True while permission is being asked for and the recorder is starting, so
  /// repeated taps cannot begin two recordings.
  var isPreparingCapture = false
  /// The calendar event the recording in progress was started from. Cleared
  /// as soon as the record is saved or discarded, so only that record keeps
  /// the link and no later recording is attached to the wrong event.
  var captureEvent: UpcomingMeeting?
  /// True while a recording is being finished and stored.
  var isSavingCapture = false
  /// True when a finished recording could not be stored. Its audio, its record
  /// and its draft are kept, and no new recording may start until it is saved
  /// or discarded, so one recording cannot replace another.
  var hasUnsavedRecording = false
  /// Drives the retry alert. Separate from `hasUnsavedRecording` so dismissing
  /// the alert does not lift the block on starting a new recording.
  var isUnsavedRecordingAlertPresented = false
  /// True while a backup restore is preparing files and before its records are
  /// written, so a record added meanwhile cannot be silently replaced.
  var isRestoring = false
  var recordingElapsed: TimeInterval = 0
  /// Smoothed 0...1 loudness for the recording glow.
  /// The glow's microphone level, kept in its own observable object so the ~22
  /// updates a second redraw only the view drawing the glow.
  @ObservationIgnored let levelMeter = RecordingLevelMeter()
  /// The live transcription shown while recording, on iOS 26 only. Display-only.
  @ObservationIgnored let realtimeTranscriber = RealtimeTranscriptionService()
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
  /// Shown when an audio file was handed to the app while recording, to say it
  /// will be imported once the recording ends.
  var pendingImportNotice: String?
  /// Count of audio files left in the Inbox (an import that was cut short), so
  /// the person can import or remove them.
  var pendingInboxCount: Int?
  /// True when a first real recording or import landed while samples are still
  /// present, so the app offers once to remove them.
  var isSampleCleanupSuggested = false
  /// Whether the display samples are still among the records. Stored rather
  /// than computed so a screen showing the samples notice only redraws when the
  /// answer changes, not whenever any of the five lists does.
  private(set) var hasSampleContent = false
  /// Set when stored data exists but could not be read. The data is kept aside
  /// rather than overwritten with samples.
  var loadFailureMessage: String?
  /// The deletion that can still be taken back, shown as a toast. A newer one
  /// finalizes the one before it, so only one offer is ever live.
  var pendingUndo: UndoAction?
  /// Set when a media file that should have been removed could not be.
  var deletionFailureMessage: String?
  /// Set when a change could not be written to the local store.
  var persistenceFailureMessage: String?
  var account: MemoraAccount?
  var isAuthPresented = false
  var isPaywallPresented = false
  var omiPairingManager = OmiPairingManager()
  /// The details currently on screen, oldest first. A stack, not one value, so a
  /// screen opened over another cannot clear the one below it when it closes.
  private(set) var activeDetailMeetingIDs: [UUID] = []
  var activeDetailMeetingID: UUID? { activeDetailMeetingIDs.last }
  /// Asked by a source line to bring the open detail to its transcript at a
  /// time, instead of stacking a second copy of the same record.
  var detailPlaybackRequest: DetailPlaybackRequest?
  /// The playback running for the detail on screen, so its transport can live in
  /// the floating controls above the composer instead of over them.
  var activePlayback: AudioPlayerService?

  func pushActiveDetail(_ id: UUID) {
    activeDetailMeetingIDs.append(id)
  }

  /// Removes this screen's own entry, leaving any screen opened above it alone.
  func popActiveDetail(_ id: UUID) {
    if let index = activeDetailMeetingIDs.lastIndex(of: id) {
      activeDetailMeetingIDs.remove(at: index)
    }
  }

  func isActiveDetail(_ id: UUID) -> Bool {
    activeDetailMeetingIDs.contains(id)
  }
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
  /// Auto-dismiss for the undo toast. Cancelled when the offer is taken or
  /// replaced, so only the live toast finalizes.
  @ObservationIgnored var undoDismissTask: Task<Void, Never>?
  private static let composerDraftKey = "composer.question"
  /// True when the store could not be read at startup. Persisting is refused
  /// while it is set, so unreadable existing data is never written over.
  @ObservationIgnored var isStoreProtected = false
  /// The engine Ask AI and summaries actually use. The model owns it, so what
  /// the composer shows and what the request calls cannot drift apart.
  var registeredLLMs = RegisteredLLMStore()
  var aiEngine: AIEngine = .automatic {
    didSet {
      UserDefaults.standard.set(aiEngine.rawValue, forKey: StorageKey.aiEngine)
    }
  }
  /// The bring-your-own-key provider used when the engine is cloud.
  var aiProvider: LLMProvider = .openAI {
    didSet {
      UserDefaults.standard.set(aiProvider.rawValue, forKey: StorageKey.aiProvider)
      guard aiProvider != oldValue else { return }
      // Each provider remembers its own model, so switching back restores it.
      aiModelID = Self.storedModelID(for: aiProvider)
    }
  }
  /// The model called at the chosen provider.
  var aiModelID: String = "" {
    didSet {
      UserDefaults.standard.set(aiModelID, forKey: StorageKey.aiModel(aiProvider))
    }
  }
  /// The provider and model a cloud request goes to, read together.
  var aiSelection: LLMSelection {
    LLMSelection(provider: aiProvider, modelID: aiModelID)
  }

  private static func storedModelID(for provider: LLMProvider) -> String {
    let stored = UserDefaults.standard.string(forKey: StorageKey.aiModel(provider)) ?? ""
    return stored.isEmpty ? provider.defaultModelID : stored
  }
  /// The request currently being answered, so a newer one can drop it.
  @ObservationIgnored var aiChatRequestID: UUID?
  @ObservationIgnored var aiChatTask: Task<Void, Never>?
  /// Resumes the agent once its pending change is approved or declined.
  @ObservationIgnored var agentApprovalContinuation: CheckedContinuation<Bool, Never>?

  /// Onboarding runs once. Sign-in and Plus stay optional so people can judge
  /// the app before committing to either.
  var hasCompletedOnboarding: Bool
  var isSubscribed: Bool
  /// The chosen tier. Billing is not connected yet, so this is a local choice
  /// that decides which features are unlocked; nil means the free plan.
  var planTier: PlanTier?
  /// True when the team tier is chosen. This is what gates team-only features.
  var hasTeamPlan: Bool { isSubscribed && planTier == .team }
  var hasOfferedPlus: Bool

  @ObservationIgnored var recordingURL: URL?
  @ObservationIgnored var recordingStartedAt: Date?
  @ObservationIgnored var recordingPausedAt: Date?
  @ObservationIgnored var recordingPausedDuration: TimeInterval = 0
  @ObservationIgnored var recordingTicker: Task<Void, Never>?
  @ObservationIgnored var levelTicker: Task<Void, Never>?
  /// Transcription and summary jobs, with the rules that decide whether a
  /// result still applies.
  @ObservationIgnored let processing = ProcessingService()
  /// Timings for the paths that matter when comparing builds. Holds numbers and
  /// names only, never content.
  @ObservationIgnored let performance = PerformanceLog.shared
  /// The person's own picture and name, shown on Settings and each tab's
  /// top-right button.
  @ObservationIgnored let profile = UserProfile()
  /// CloudKit team sharing. Kept out of the local write path: it runs only when
  /// the person shares something or opens the team list.
  @ObservationIgnored let cloudSharing = CloudSharingService.shared
  /// The share the system sharing sheet is presenting, if any.
  var pendingCloudShare: CloudSharingService.ShareRequest?
  /// A team-sharing message to show, whether a refusal or a failure.
  var cloudShareMessage: String?
  /// What a recording in progress would need to be recovered after a stop.
  @ObservationIgnored var recordingDraft: RecordingDraft?
  /// Media whose record is already gone but whose files could not be removed.
  /// Kept so the removal can be tried again instead of being dropped silently.
  @ObservationIgnored var pendingMediaDeletions: [PendingMediaDeletion] = []
  @ObservationIgnored var recordingActivity: Activity<MemoraRecordingAttributes>?
  @ObservationIgnored var pendingMeetingNavigationID: UUID?
  /// True when a real save should offer to clear the samples once the capture
  /// sheet has closed, so the alert is not raised while a sheet is dismissing.
  @ObservationIgnored var pendingSampleCleanupSuggestion = false
  @ObservationIgnored let recorder = AudioRecorderService()

  init() {
    let defaults = UserDefaults.standard
    RecordStore.prepare()
    performance.loadStored()
    let launchStartedAt = Date()

    hasCompletedOnboarding = defaults.bool(forKey: StorageKey.hasCompletedOnboarding)
    isSubscribed = defaults.bool(forKey: StorageKey.isSubscribed)
    planTier = PlanTier(rawValue: defaults.string(forKey: StorageKey.planTier) ?? "")
    hasOfferedPlus = defaults.bool(forKey: StorageKey.hasOfferedPlus)
    aiEngine = AIEngine(rawValue: defaults.string(forKey: StorageKey.aiEngine) ?? "") ?? .automatic
    let storedProvider = LLMProvider(rawValue: defaults.string(forKey: StorageKey.aiProvider) ?? "") ?? .openAI
    aiProvider = storedProvider
    aiModelID = Self.storedModelID(for: storedProvider)
    composerDraft = DraftStore.load(Self.composerDraftKey) ?? ""
    // Cloud storage is a paid option: without Plus the records stay on device.
    cloudStorageEnabled = defaults.bool(forKey: StorageKey.isSubscribed)
      && defaults.bool(forKey: StorageKey.cloudStorage)
    if case .data(let data) = RecordStore.load(StorageKey.account) {
      account = try? JSONDecoder().decode(MemoraAccount.self, from: data)
    }

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

    // A first run starts empty. Sample content is only added when the person
    // chooses it from onboarding, so their own records are never mixed with it.
    meetings = load([Meeting].self, forKey: StorageKey.meetings, fallback: [])
    spaces = load([MemoraSpace].self, forKey: StorageKey.spaces, fallback: [])
    documents = load([MemoraDocument].self, forKey: StorageKey.documents, fallback: [])
    lifeLogEntries = load([LifeLogEntry].self, forKey: StorageKey.lifeLogEntries, fallback: [])
    tasks = load([MemoraTask].self, forKey: StorageKey.tasks, fallback: [])
    people = load([Person].self, forKey: StorageKey.people, fallback: [])
    let activeJobIDs = load([String].self, forKey: StorageKey.activeJobs, fallback: [])
    processing.restoreInterrupted(activeJobIDs)
    trashedRecords = load([TrashedRecord].self, forKey: StorageKey.trash, fallback: [])
    trashedLifeLogEntries = load(
      [TrashedLifeLogEntry].self,
      forKey: StorageKey.lifeLogTrash,
      fallback: []
    )
    pendingMediaDeletions = load(
      [PendingMediaDeletion].self,
      forKey: StorageKey.pendingMediaDeletions,
      fallback: []
    )
    // The recording draft is what a recovery depends on, so a failure to read it
    // counts like any other: the store is treated as unreadable and nothing is
    // written over it. A draft that cannot be decoded is set aside the same way
    // an unreadable record is.
    switch RecordStore.load(StorageKey.recordingDraft) {
    case .absent:
      break
    case .failed:
      didFailToReadStore = true
    case .data(let draftData):
      if let decoded = try? JSONDecoder().decode(RecordingDraft.self, from: draftData) {
        recordingDraft = decoded
        // A draft from an older build has no id; give it a stable one now so a
        // recovery that is cut off and retried does not make a second record.
        if recordingDraft?.id == nil {
          recordingDraft?.id = UUID()
        }
      } else if RecordStore.quarantine(draftData, key: StorageKey.recordingDraft) {
        didFindUnreadableData = true
      } else {
        didFailToReadStore = true
      }
    }

    installedTemplateIDs = defaults.stringArray(forKey: StorageKey.installedTemplates) ?? []
    aiHistory = load([AIConversationEntry].self, forKey: StorageKey.aiHistory, fallback: [])

    // Protection is decided only once every document has been read, so a failure
    // in the last one (AI history, say) still stops the app from overwriting it.
    isStoreProtected = didFailToReadStore

    // Photos that older records held inline are written to files here, after
    // loading, so decoding a document (a backup, say) never writes into the
    // app's folders as a side effect. A record whose photos could not all be
    // written keeps its bytes, so nothing is lost; the person is told.
    var didFailToMigratePhotos = false
    if meetings.contains(where: { $0.legacyPhotoData != nil }) {
      var materialized = meetings
      for index in materialized.indices where materialized[index].legacyPhotoData != nil {
        if !materialized[index].materializeLegacyPhotos() {
          didFailToMigratePhotos = true
        }
      }
      meetings = materialized
    }

    if didFailToReadStore {
      loadFailureMessage = "保存データを読み込めませんでした。データを壊さないため、この起動では保存を停止しています。アプリを再起動してください。"
    } else if didFindUnreadableData {
      loadFailureMessage = "保存されたデータの一部を読み込めませんでした。元のデータは端末に退避しています。"
    } else if didFailToMigratePhotos {
      loadFailureMessage = "古い形式の写真を移行できませんでした。写真は失われないよう記録に残しています。空き容量を確認して、アプリを再起動してください。"
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

    // A removal of media that failed last time is tried again.
    retryPendingMediaDeletions()

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
    refreshSampleContentFlag()

    // Automatic records the logger wrote while no model existed are brought in.
    importAutoLifeLogInbox()

    // Any reminders that changed while the app was away are brought up to date.
    TaskReminderScheduler.refreshAll(tasks)

    // Audio left in the Inbox by a cut-short import is offered back.
    scanInboxForAudio()

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

    // A record the logger writes while the app is open is taken in at once, so
    // it does not wait for the next time the app is activated.
    inboxObserver = NotificationCenter.default.addObserver(
      forName: .autoLifeLogInboxDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.importAutoLifeLogInbox() }
    }

    // A tapped task reminder opens the tasks tab with that task's editor.
    taskReminderObserver = NotificationCenter.default.addObserver(
      forName: .taskReminderTapped,
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let id = note.userInfo?["taskID"] as? UUID else { return }
      Task { @MainActor in
        self?.selectedTab = .tasks
        self?.pendingTaskEditID = id
      }
    }

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
    // Sorted once, so every group below is already newest first.
    let newestFirst = meetings.sorted { $0.createdAt > $1.createdAt }
    var bySpace: [UUID: [Meeting]] = [:]
    var byPerson: [UUID: [Meeting]] = [:]
    for meeting in newestFirst {
      if let spaceID = meeting.spaceID {
        bySpace[spaceID, default: []].append(meeting)
      }
      for personID in meeting.participantIDs ?? [] {
        byPerson[personID, default: []].append(meeting)
      }
    }

    let aggregates = bySpace.mapValues { group in
      SpaceAggregate(
        meetingCount: group.count,
        icons: group.prefix(4).map { $0.source == .recording ? .waveform : .squareAndArrowDown },
        latestDate: group.first?.createdAt
      )
    }
    // Every assignment redraws each screen that reads the value, and most edits
    // (a progress tick while transcribing, a renamed record) change none of
    // these, so they are only replaced when they differ.
    assignIfChanged(\.spaceAggregates, aggregates)
    assignIfChanged(\.personMeetingCounts, byPerson.mapValues(\.count))
    assignIfChanged(\.meetingsByPerson, byPerson)
    assignIfChanged(
      \.meetingTitles,
      Dictionary(meetings.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    )
  }

  /// Groups the journal by day once, newest first.
  private func rebuildLifeLogDays() {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: lifeLogEntries) { calendar.startOfDay(for: $0.createdAt) }
    let days = grouped
      .map { LifeLogDayGroup(day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
      .sorted { $0.day > $1.day }
    // A day change that moves nothing leaves the journal as it was.
    assignIfChanged(\.lifeLogDays, days)
    assignIfChanged(\.markedLifeLogDays, Set(grouped.keys))
  }

  private func refreshSampleContentFlag() {
    let hasSamples = meetings.contains { SampleContent.isSample(meetingID: $0.id) }
      || spaces.contains { SampleContent.isSample(spaceID: $0.id) }
      || tasks.contains { SampleContent.isSample(task: $0) }
      || lifeLogEntries.contains { SampleContent.isSample(lifeLogEntry: $0) }
      || people.contains { SampleContent.isSample(personID: $0.id) }
    assignIfChanged(\.hasSampleContent, hasSamples)
  }

  private func assignIfChanged<Value: Equatable>(
    _ keyPath: ReferenceWritableKeyPath<MemoraModel, Value>,
    _ value: Value
  ) {
    if self[keyPath: keyPath] != value {
      self[keyPath: keyPath] = value
    }
  }

  /// Re-reads the on-device documents for pull-to-refresh, so a change written
  /// since launch (a restored backup, say) is picked up. A document that is
  /// missing or unreadable is left as-is rather than cleared.
  func refresh() async {
    // Let every queued save land first, so the reload below cannot read an
    // older copy than what is on screen.
    await RecordStore.flushAsync()
    if let stored = Self.storedDocument([Meeting].self, forKey: StorageKey.meetings) {
      meetings = stored
    }
    if let stored = Self.storedDocument([MemoraSpace].self, forKey: StorageKey.spaces) {
      spaces = stored
    }
    if let stored = Self.storedDocument([MemoraDocument].self, forKey: StorageKey.documents) {
      documents = stored
    }
    if let stored = Self.storedDocument([LifeLogEntry].self, forKey: StorageKey.lifeLogEntries) {
      lifeLogEntries = stored
    }
    if let stored = Self.storedDocument([MemoraTask].self, forKey: StorageKey.tasks) {
      tasks = stored
    }
    if let stored = Self.storedDocument([Person].self, forKey: StorageKey.people) {
      people = stored
    }
  }

  private static func storedDocument<T: Decodable>(_ type: [T].Type, forKey key: String) -> [T]? {
    guard case .data(let data) = RecordStore.load(key) else { return nil }
    return try? JSONDecoder().decode([T].self, from: data)
  }


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

  /// Tells VoiceOver about a change it cannot see, such as a recording that
  /// started or a transcript that finished.
  func announce(_ message: String) {
    UIAccessibility.post(notification: .announcement, argument: message)
  }
}
