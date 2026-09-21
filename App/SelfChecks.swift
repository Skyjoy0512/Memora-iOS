#if DEBUG
import Foundation

/// Quick checks that run in debug builds only, until the project has a test
/// target. They cover the pieces most likely to break silently: the markdown
/// round trip used by inline editing, and the draft store. Failures are logged
/// rather than fatal, so a debug build never crashes over a check.
@MainActor
enum SelfChecks {
  static func run() {
    checkMarkdownRoundTrip("**太字**", name: "bold")
    checkMarkdownRoundTrip("*斜体*", name: "italic")
    checkMarkdownRoundTrip("`code`", name: "code")
    checkMarkdownRoundTrip("~~取り消し~~", name: "strikethrough")
    checkMarkdownRoundTrip("[リンク](https://example.com)", name: "link")
    checkMarkdownRoundTrip("1行目\n**2行目**\n3行目", name: "newlines")
    checkMarkdownRoundTrip("そのままの日本語テキスト", name: "plain text")

    let key = "selfcheck.draft"
    DraftStore.save("下書きのテスト", key: key)
    if DraftStore.load(key) != "下書きのテスト" {
      report("draft round trip")
    }
    DraftStore.clear(key)
    if DraftStore.load(key) != nil {
      report("draft clear")
    }

    checkQuestionWords()
    checkScopeIsolation()
    checkProcessingRevision()
    checkMediaPaths()
    checkPhotoFileRoles()
    checkRequestScope()
    checkPhotoThumbnailNaming()

    checkAudioSessionClaims()
    checkStoreFailureInjection()

    // Ordering cannot be checked synchronously; it runs beside the app.
    Task { await checkProcessingRunOwnership() }
    checkStatusFilter()
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

  private static func report(_ name: String) {
    print("SelfCheck failed — \(name)")
  }
}
#endif
