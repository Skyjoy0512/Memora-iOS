#if DEBUG
import Foundation

/// Quick checks that run in debug builds only, until the project has a test
/// target. They cover the pieces most likely to break silently. Failures are
/// printed and recorded, not fatal, so a debug build never crashes over a check.
///
/// These are not proof that the app works: a check that fails only prints. What
/// they can do is show, on a debug screen, which pieces were exercised and
/// whether they passed, so a run on a real device is reviewable.
@MainActor
enum SelfChecks {
  struct Result: Identifiable {
    var name: String
    var passed: Bool
    var detail: String?
    var ranAt: Date
    var build: String

    var id: String { name }
  }

  /// What the last run found, newest run only, so a debug screen can show it.
  private(set) static var results: [Result] = []

  static func run() {
    results = []
    failures = 0
    lastDetail = nil

    group("Markdown round trip") {
      checkMarkdownRoundTrip("**太字**", name: "bold")
      checkMarkdownRoundTrip("*斜体*", name: "italic")
      checkMarkdownRoundTrip("`code`", name: "code")
      checkMarkdownRoundTrip("~~取り消し~~", name: "strikethrough")
      checkMarkdownRoundTrip("[リンク](https://example.com)", name: "link")
      checkMarkdownRoundTrip("1行目\n**2行目**\n3行目", name: "newlines")
      checkMarkdownRoundTrip("そのままの日本語テキスト", name: "plain text")
    }

    group("Draft store", checkDraftStore)
    group("Draft legacy format", checkDraftLegacyFormat)
    group("Store migration", checkStoreMigration)

    group("Question terms", checkQuestionWords)
    group("Scope isolation", checkScopeIsolation)
    group("Processing input revision", checkProcessingRevision)
    group("Media paths", checkMediaPaths)
    group("Photo file roles", checkPhotoFileRoles)
    group("Request scope", checkRequestScope)
    group("Photo thumbnail naming", checkPhotoThumbnailNaming)
    group("Status filter", checkStatusFilter)
    group("Audio session claims", checkAudioSessionClaims)
    group("Store failure injection", checkStoreFailureInjection)
    group("Atomic commit", checkAtomicCommit)
    group("Backup restore validation", checkBackupRestoreValidation)
    group("Speech final results", checkSpeechFinalResults)

    // Ordering cannot be checked synchronously; it runs beside the app and adds
    // its result when it finishes.
    group("Processing run ownership", isAsync: true) {}
    Task { await runOwnershipCheck() }
  }

  /// Runs one named check and records whether it passed, so the debug screen can
  /// show it instead of leaving the answer in the console.
  private static func group(_ name: String, isAsync: Bool = false, _ body: () -> Void) {
    let failuresBefore = failures
    let detailBefore = lastDetail
    body()
    let passed = failures == failuresBefore
    results.append(
      Result(
        name: name,
        passed: passed,
        detail: passed ? nil : (lastDetail ?? detailBefore),
        ranAt: .now,
        build: Bundle.main.appVersion
      )
    )
  }

  /// A summary must not be applied to a transcript that changed while it was
  /// being written, so the fingerprint has to notice an edit — including one
  /// that keeps the same number of characters.
  private static func checkProcessingRevision() {
    let segment = TranscriptSegment(
      id: UUID(),
      speaker: "話者",
      speakerIsCertain: false,
      timestamp: 0,
      text: "最初の内容"
    )
    let before = ProcessingService.inputRevision([segment])
    var edited = segment
    edited.text = "直した内容"
    if ProcessingService.inputRevision([edited]) == before {
      report("processing input revision did not change")
    }
    if ProcessingService.inputRevision([segment]) != before {
      report("processing input revision is not stable")
    }
  }

  /// A photo's thumbnail is found from the stored name, and both files belong to
  /// the record so a backup carries them together.
  private static func checkPhotoThumbnailNaming() {
    let name = "ABC.jpg"
    if MediaFiles.photoFiles(for: [name]) != [name, "ABC.jpg.thumb.jpg"] {
      report("photo thumbnail naming: \(MediaFiles.photoFiles(for: [name]))")
    }
  }

  /// A question asked of one meeting, or one project, must not carry another
  /// record's contents. This checks the request the app would send, without
  /// calling any engine.
  private static func checkRequestScope() {
    let meetingA = Meeting(
      id: UUID(),
      title: "会議A",
      createdAt: .now,
      duration: 60,
      source: .recording,
      status: .ready,
      summary: "A社との見積もり",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: []
    )
    let meetingB = Meeting(
      id: UUID(),
      title: "会議B",
      createdAt: .now,
      duration: 60,
      source: .recording,
      status: .ready,
      summary: "B社との採用",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: []
    )

    let fileRequest = AIQuestionRequest(question: "見積もりは？", scope: .file(meetingA.id), attachment: nil)
    let fileAllowed = MemoraModel.meetings(in: fileRequest.scope, from: [meetingA, meetingB])
    let fileContent = MemoraModel.requestContent(
      for: fileRequest,
      scopeLabel: "会議A",
      allowedMeetings: fileAllowed,
      tasks: []
    )
    if !fileContent.context.contains("A社との見積もり") {
      report("request content missed the allowed record")
    }
    if fileContent.context.contains("B社との採用") {
      report("request content carried a record outside the range")
    }
    if fileContent.sources.map(\.meetingID) != [meetingA.id] {
      report("request sources outside the range: \(fileContent.sources.map(\.title))")
    }

    let spaceID = UUID()
    var inProject = meetingA
    inProject.spaceID = spaceID
    let spaceRequest = AIQuestionRequest(question: "", scope: .space(spaceID), attachment: nil)
    let spaceAllowed = MemoraModel.meetings(in: spaceRequest.scope, from: [inProject, meetingB])
    let spaceContent = MemoraModel.requestContent(
      for: spaceRequest,
      scopeLabel: "プロジェクト",
      allowedMeetings: spaceAllowed,
      tasks: []
    )
    if spaceContent.sources.map(\.meetingID).contains(meetingB.id) {
      report("project range carried a record outside it")
    }
  }

  /// A stored media name must be a plain file name, and nothing outside the
  /// managed folder may ever be resolved or erased.
  private static func checkMediaPaths() {
    for bad in ["", ".", "..", "a/b", "../b", "/abs", "a\\b"] where MediaFiles.isPlainName(bad) {
      report("media name accepted: \(bad.debugDescription)")
    }
    for good in ["abc.m4a", "abc.jpg", "abc.jpg.thumb.jpg"] where !MediaFiles.isPlainName(good) {
      report("media name rejected: \(good)")
    }

    let folder = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)
    if MediaFiles.isInside(folder, folder: folder) {
      report("media folder counted as inside itself")
    }
    if MediaFiles.isInside(URL(fileURLWithPath: "/tmp/RecordingsOld/x.m4a"), folder: folder) {
      report("a shared name prefix counted as inside")
    }
    if !MediaFiles.isInside(URL(fileURLWithPath: "/tmp/Recordings/x.m4a"), folder: folder) {
      report("a file in the folder was not counted as inside")
    }
  }

  /// An original is required for a backup; a thumbnail can always be built again.
  private static func checkPhotoFileRoles() {
    if MediaFiles.requiredPhotoFiles(for: "A.jpg") != ["A.jpg"] {
      report("required photo files: \(MediaFiles.requiredPhotoFiles(for: "A.jpg"))")
    }
    if MediaFiles.regenerablePhotoFiles(for: "A.jpg") != ["A.jpg.thumb.jpg"] {
      report("regenerable photo files: \(MediaFiles.regenerablePhotoFiles(for: "A.jpg"))")
    }
  }

  /// The state filter both lists share: a record is finished when it is ready.
  private static func checkStatusFilter() {
    if !SearchFilters.Status.finished.matches(.ready) {
      report("status filter: ready is not finished")
    }
    if SearchFilters.Status.finished.matches(.transcribing(0.5)) {
      report("status filter: transcribing counted as finished")
    }
    if !SearchFilters.Status.needsAttention.matches(.failed("x")) {
      report("status filter: failed is not needs attention")
    }
  }

  /// A question asked of a project must not carry records or tasks from outside
  /// a project, so a scoped answer cannot rest on the wrong data.
  private static func checkScopeIsolation() {
    let spaceID = UUID()
    let inProject = Meeting(
      id: UUID(),
      title: "プロジェクトの会議",
      createdAt: .now,
      duration: 60,
      source: .recording,
      status: .ready,
      summary: "要約",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: [],
      spaceID: spaceID
    )
    let loose = Meeting(
      id: UUID(),
      title: "未分類の会議",
      createdAt: .now,
      duration: 60,
      source: .recording,
      status: .ready,
      summary: "",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: []
    )

    let scopedMeetings = MemoraModel.meetings(in: .projects, from: [inProject, loose])
    if scopedMeetings.map(\.id) != [inProject.id] {
      report("scope meetings: \(scopedMeetings.map(\.title))")
    }

    let tasks = [
      MemoraTask(id: UUID(), title: "プロジェクトのタスク", meetingID: inProject.id, isCompleted: false),
      MemoraTask(id: UUID(), title: "未分類のタスク", meetingID: loose.id, isCompleted: false)
    ]
    let scopedTasks = MemoraModel.openTasks(in: .projects, from: tasks, meetings: [inProject, loose])
    if scopedTasks.map(\.title) != ["プロジェクトのタスク"] {
      report("scope tasks: \(scopedTasks.map(\.title))")
    }
  }

  /// Ask AI reaches records by the words of the question; a Japanese question
  /// has no spaces, so it must be cut into pieces that can still be found.
  private static func checkQuestionWords() {
    let terms = MemoraModel.questionWords(in: "会議の決定は？")
    for expected in ["会議", "決定"] {
      if !terms.contains(expected) {
        report("question words missing \(expected): \(terms)")
      }
    }
    if terms.contains(where: { $0.contains("？") || $0.contains("?") }) {
      report("question words kept punctuation: \(terms)")
    }
  }

  /// Only settled results become transcript lines, and nothing is merged or
  /// dropped for being close in time or said twice.
  private static func checkSpeechFinalResults() {
    func line(_ text: String, _ timestamp: TimeInterval, isFinal: Bool) -> TranscriptSegment? {
      SpeechTranscriptionSegments.segment(
        from: SpeechTranscriptionUpdate(text: text, timestamp: timestamp, isFinal: isFinal)
      )
    }

    // Volatile progress is not stored, and an empty result stores nothing.
    if line("こんにちは", 0, isFinal: false) != nil {
      report("a volatile result became a transcript line")
    }
    if line("   ", 0, isFinal: true) != nil {
      report("an empty result became a transcript line")
    }

    // Two settled phrases close together both stay.
    let near = [line("はい", 1.00, isFinal: true), line("はい、進めましょう", 1.02, isFinal: true)]
    if near.compactMap({ $0 }).count != 2 {
      report("near-in-time results were merged: \(near.compactMap { $0?.text })")
    }

    // The same words said twice stay twice.
    let repeated = [line("はい", 1, isFinal: true), line("はい", 5, isFinal: true)]
    if repeated.compactMap({ $0 }).count != 2 {
      report("a repeated phrase was dropped")
    }

    // The time is kept as the engine reported it.
    if line("発言", 12.5, isFinal: true)?.timestamp != 12.5 {
      report("the result time was not kept")
    }
  }

  /// A draft must come back exactly as it went in: newlines, quotes, Japanese
  /// and the empty string alike, with no escaping added and nothing dropped.
  private static func checkDraftStore() {
    let key = "selfcheck.draft"
    let samples = ["下書きのテスト", "1行目\n2行目", "引用符\"と'", "", "日本語\n\"複数\"\n行"]
    for text in samples {
      do {
        try DraftStore.saveAndWait(text, key: key)
      } catch {
        report("draft save failed: \(error)")
        continue
      }
      if DraftStore.load(key) != text {
        report("draft round trip: \(text.debugDescription) -> \(String(describing: DraftStore.load(key)))")
      }
    }
    DraftStore.clear(key)
    if DraftStore.load(key) != nil {
      report("draft clear")
    }
  }

  /// A draft written by the old build was a JSON string read back as raw text.
  /// It must decode to the original body once, not keep the quotes and escapes.
  private static func checkDraftLegacyFormat() {
    let key = "selfcheck.draft.legacy"
    let original = "旧\"下書き\"\n2行目"
    do {
      let stored = try JSONEncoder().encode(original)
      try RecordStore.saveDataNow(stored, key: "draft." + key)
    } catch {
      report("legacy draft could not be staged: \(error)")
      return
    }
    if DraftStore.load(key) != original {
      report("legacy draft was not decoded: \(String(describing: DraftStore.load(key)))")
    }
    DraftStore.clear(key)
  }

  /// The move off `UserDefaults` happens once per key. A failed move keeps the
  /// old copy and can be retried, and a removed document stays removed.
  private static func checkStoreMigration() {
    let key = "selfcheck.migration"
    let marker = key + ".migrated"
    let legacy = Data("legacy".utf8)
    UserDefaults.standard.set(legacy, forKey: key)
    try? RecordStore.remove(marker)

    // A failed migration must report failure and leave the old copy in place.
    RecordStore.setFailureInjection(true)
    if case .failed = RecordStore.load(key) {
      // Expected.
    } else {
      report("a failed migration did not report failure")
    }
    if UserDefaults.standard.data(forKey: key) != legacy {
      report("a failed migration dropped the old copy")
    }

    // The next attempt succeeds, because nothing was written on the failure.
    guard case .data(let migrated) = RecordStore.load(key), migrated == legacy else {
      report("the migration could not be retried")
      try? RecordStore.remove(key)
      try? RecordStore.remove(marker)
      UserDefaults.standard.removeObject(forKey: key)
      return
    }

    // Removing the document must not bring the old copy back.
    try? RecordStore.remove(key)
    if case .data = RecordStore.load(key) {
      report("a removed document was migrated in again")
    }

    try? RecordStore.remove(marker)
    UserDefaults.standard.removeObject(forKey: key)
  }

  /// A commit that stores records and removes their draft must do both or
  /// neither, so a record can never be saved beside a live draft, and a failed
  /// commit must leave the draft and the documents as they were.
  private static func checkAtomicCommit() {
    let docA = "selfcheck.commit.a"
    let docB = "selfcheck.commit.b"
    let draft = "selfcheck.commit.draft"
    let draftStorageKey = "draft." + draft
    DraftStore.save("下書き", key: draft)

    do {
      try RecordStore.commitNow(
        writes: [
          (key: docA, data: Data("A".utf8)),
          (key: docB, data: Data("B".utf8)),
        ],
        removing: [draftStorageKey]
      )
    } catch {
      report("atomic commit failed: \(error)")
    }
    if DraftStore.load(draft) != nil {
      report("the commit did not remove the draft")
    }
    if case .data(let data) = RecordStore.load(docA), data == Data("A".utf8) {
      // Expected.
    } else {
      report("the commit did not store the first document")
    }

    // A failing commit changes nothing: the draft stays and the documents keep
    // their previous contents.
    DraftStore.save("下書き2", key: draft)
    RecordStore.setFailureInjection(true)
    do {
      try RecordStore.commitNow(
        writes: [
          (key: docA, data: Data("A2".utf8)),
          (key: docB, data: Data("B2".utf8)),
        ],
        removing: [draftStorageKey]
      )
      report("a failing commit reported success")
    } catch {
      // Expected.
    }
    if DraftStore.load(draft) != "下書き2" {
      report("a failing commit changed the draft")
    }
    if case .data(let data) = RecordStore.load(docA), data == Data("A".utf8) {
      // Expected: the earlier value is untouched.
    } else {
      report("a failing commit changed a document")
    }

    try? RecordStore.remove(docA)
    try? RecordStore.remove(docB)
    DraftStore.clear(draft)
  }

  /// A backup is checked by kind: a name cannot be both audio and photo, and a
  /// listed file must be a regular file, so a folder or a symlink is refused
  /// rather than copied into the app's media folders.
  private static func checkBackupRestoreValidation() {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
      .appendingPathComponent("selfcheck-backup-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }

    let packageURL = root.appendingPathComponent("backup", isDirectory: true)
    let mediaURL = packageURL.appendingPathComponent(BackupPackage.mediaFolderName, isDirectory: true)
    do {
      try fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
      try Data("audio".utf8).write(to: mediaURL.appendingPathComponent("a.m4a"))
      try Data("photo".utf8).write(to: mediaURL.appendingPathComponent("p.jpg"))
      try Data("x".utf8).write(to: mediaURL.appendingPathComponent("target.m4a"))
      try fileManager.createSymbolicLink(
        atPath: mediaURL.appendingPathComponent("link.m4a").path,
        withDestinationPath: "target.m4a"
      )
      try fileManager.createDirectory(
        at: mediaURL.appendingPathComponent("dir.m4a", isDirectory: true),
        withIntermediateDirectories: true
      )
    } catch {
      report("backup self-check could not build a package: \(error)")
      return
    }

    func writeManifest(_ manifest: BackupPackage.Manifest) -> Bool {
      do {
        try JSONEncoder().encode(manifest).write(
          to: packageURL.appendingPathComponent(BackupPackage.manifestName),
          options: .atomic
        )
        return true
      } catch {
        report("backup self-check could not write a manifest: \(error)")
        return false
      }
    }

    func manifest(audio: [String], photo: [String]) -> BackupPackage.Manifest {
      BackupPackage.Manifest(
        version: BackupPackage.currentVersion,
        exportedAt: .now,
        meetings: [],
        spaces: [],
        tasks: [],
        lifeLogEntries: [],
        people: [],
        aiHistory: [],
        audioFileNames: audio,
        photoFileNames: photo
      )
    }

    // A name in both lists is a conflict.
    if writeManifest(manifest(audio: ["a.m4a", "p.jpg"], photo: ["p.jpg"])) {
      do {
        _ = try BackupPackage.read(from: packageURL)
        report("a file listed as both audio and photo was accepted")
      } catch BackupPackage.BackupError.conflictingMedia {
        // Expected.
      } catch {
        report("unexpected backup error for a kind conflict: \(error)")
      }
    }

    // A symlink or a folder is not media.
    for bad in ["link.m4a", "dir.m4a"] where writeManifest(manifest(audio: [bad], photo: [])) {
      do {
        _ = try BackupPackage.read(from: packageURL)
        report("a non-regular file was accepted as media: \(bad)")
      } catch BackupPackage.BackupError.missingMedia {
        // Expected.
      } catch {
        report("unexpected backup error for \(bad): \(error)")
      }
    }

    // A good package is accepted.
    if writeManifest(manifest(audio: ["a.m4a"], photo: ["p.jpg"])) {
      do {
        _ = try BackupPackage.read(from: packageURL)
      } catch {
        report("a valid package was refused: \(error)")
      }
    }
  }

  /// A failing write must be reported to the caller, and the store must still
  /// work afterwards, so an error is a real outcome rather than a silent drop.
  private static func checkStoreFailureInjection() {
    let key = "selfcheck.injection"
    RecordStore.setFailureInjection(true)
    do {
      try RecordStore.saveNow("値", key: key)
      report("a failing write reported success")
    } catch {
      // Expected.
    }

    // The injected failure is used up, so the store works again.
    do {
      try RecordStore.saveNow("値", key: key)
    } catch {
      report("the store did not recover after a failure: \(error)")
    }
    let stored = RecordStore.load(key)
    guard case .data(let data) = stored, String(data: data, encoding: .utf8) == "\"値\"" else {
      report("the recovered write was not stored")
      try? RecordStore.remove(key)
      return
    }
    try? RecordStore.remove(key)
  }

  /// Only the feature holding the audio session may take or give it up, and a
  /// recording keeps it against everything else — including a release from a
  /// feature that does not own it.
  private static func checkAudioSessionClaims() {
    let coordinator = AudioSessionCoordinator()

    if !coordinator.claim(.speechInput) {
      report("voice input could not claim a free session")
    }
    if coordinator.claim(.playback) {
      report("playback claimed the session while voice input held it")
    }
    if coordinator.refusal(for: .playback) == nil {
      report("no reason given for a busy session")
    }
    coordinator.release(.playback)
    if coordinator.claim(.playback) {
      report("a feature that did not hold the session released it")
    }

    coordinator.beginRecording()
    if coordinator.claim(.speechInput) {
      report("voice input claimed the session during a recording")
    }
    coordinator.release(.speechInput)
    if !coordinator.isRecording {
      report("a stray release ended a recording")
    }
    coordinator.endRecording()
    if !coordinator.claim(.playback) {
      report("playback could not claim the session after a recording")
    }
    coordinator.release(.playback)
  }

  /// A gate the checks can wait on, so an order is set by the work itself rather
  /// than by sleeping and hoping.
  @MainActor
  private final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
      guard !isOpen else { return }
      await withCheckedContinuation { continuation in
        waiters.append(continuation)
      }
    }

    func open() {
      isOpen = true
      for waiter in waiters {
        waiter.resume()
      }
      waiters = []
    }
  }

  /// An old job that is cancelled, replaced, and only then finishes must not
  /// apply its result or clear the new job's record of running.
  private static func checkProcessingRunOwnership() async {
    let service = ProcessingService()
    let id = UUID()

    let oldGate = Gate()
    let oldFinished = Gate()
    service.run(id: id) {
      await oldGate.wait()
      oldFinished.open()
      return "old"
    } apply: { _ in
      report("a replaced job applied its result")
    }

    service.cancel(id)
    if service.isActive(id) {
      report("a cancelled job is still marked as running")
    }

    let newGate = Gate()
    let newFinished = Gate()
    var applied: [String] = []
    service.run(id: id) {
      await newGate.wait()
      newFinished.open()
      return "new"
    } apply: { value in
      applied.append(value)
    }
    if !service.isActive(id) {
      report("a running job is not marked as running")
    }

    // Let the replaced job finish while the new one is still running.
    oldGate.open()
    await oldFinished.wait()
    await Task.yield()
    if !service.isActive(id) {
      report("a late old job cleared the new job's running state")
    }
    if !applied.isEmpty {
      report("a replaced job applied after being replaced")
    }

    newGate.open()
    await newFinished.wait()
    await Task.yield()
    if applied != ["new"] {
      report("the running job did not apply its result: \(applied)")
    }
    if service.isActive(id) {
      report("a finished job is still marked as running")
    }
  }

  /// The editor parses markdown for display and writes it back; the text must
  /// survive that trip so formatting and line breaks are never quietly lost.
  private static func checkMarkdownRoundTrip(_ markdown: String, name: String) {
    let rendered = InlineMarkdownEditor.attributed(markdown)
    let restored = InlineMarkdownEditor.markdown(from: rendered)

    if restored != markdown {
      report("markdown \(name): \(markdown.debugDescription) → \(restored.debugDescription)")
    }
  }

  /// Counted so a named group can tell whether anything inside it failed, and
  /// printed as before.
  private static var failures = 0
  private static var lastDetail: String?

  private static func report(_ name: String) {
    failures += 1
    lastDetail = name
    print("SelfCheck failed — \(name)")
  }

  /// Runs the ordering check beside the app and fills in its place in the list.
  private static func runOwnershipCheck() async {
    let failuresBefore = failures
    await checkProcessingRunOwnership()
    let passed = failures == failuresBefore
    guard let index = results.firstIndex(where: { $0.name == "Processing run ownership" }) else { return }
    results[index].passed = passed
    results[index].detail = passed ? nil : lastDetail
  }
}
#endif
