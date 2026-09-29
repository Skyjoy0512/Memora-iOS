#if DEBUG
import Foundation
import UIKit

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

    group("Journal timeline", checkJournalTimeline)
    group("Question terms", checkQuestionWords)
    group("AI context limits", checkAIContextLimits)
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
    group("Attachment read limit", checkAttachmentReadLimit)
    group("Unassigned task scope", checkUnassignedTaskScope)
    group("Legacy photo retention", checkLegacyPhotoRetention)
    group("Speech final results", checkSpeechFinalResults)
    group("Icon assets", checkIconAssets)
    group("LLM providers", checkLLMProviders)
    group("Summary reply parsing", checkSummaryReplyParsing)
    group("Summary fallback extraction", checkSummaryFallbackExtraction)
    group("Summary action dates", checkSummaryActionDates)
    group("Summary document blocks", checkSummaryDocumentBlocks)
    group("Slide outline round trip", checkSlideOutline)
    group("Presentation package", checkPresentationPackage)
    group("Weekly review", checkWeeklyReview)
    group("Person name matching", checkPersonNames)

    // Ordering cannot be checked synchronously; it runs beside the app and adds
    // its result when it finishes.
    group("Processing run ownership", isAsync: true) {}
    Task { await runOwnershipCheck() }
    group("Recording stop order", isAsync: true) {}
    Task { await runRecordingStopOrderCheck() }
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

  /// Every icon the code can name must exist as an SF Symbol; a name that no
  /// longer resolves would otherwise draw nothing, silently.
  /// A reply with its data block: the document is kept apart from the block,
  /// "未定" never becomes an owner, and a repeated action is filed once.
  private static func checkSummaryReplyParsing() {
    let reply = """
    # 定例
    ## トピック1：予算
    本文

    <memora-data>
    {"keyPoints": ["予算を確定"], "decisions": ["上限は100万円"], "openQuestions": [],
     "actions": [{"title": "見積もり送付", "detail": "", "owner": "@Speaker 2", "due": "未定"},
                 {"title": "見積もり 送付", "detail": "", "owner": "未定", "due": "2026-10-09"}]}
    </memora-data>
    """
    let summary = SummaryResponseParser.parse(reply)
    if summary.markdown.contains("memora-data") { report("data block left in document") }
    if !summary.markdown.hasPrefix("# 定例") { report("document start lost") }
    if summary.decisions != ["上限は100万円"] { report("decisions: \(summary.decisions)") }
    if summary.actions.count != 1 { report("duplicate action kept: \(summary.actions.count)") }
    if summary.actions.first?.owner != "Speaker 2" { report("owner: \(String(describing: summary.actions.first?.owner))") }
    if summary.actions.first?.due != nil { report("未定 kept as due") }
  }

  /// Without a data block, the table and the bullets under their headings are
  /// read back; bullets under 予定アクション do not duplicate the table.
  private static func checkSummaryFallbackExtraction() {
    let document = """
    ## トピック1：SID
    ### サマリー
    - **決定事項**:
      - SIDを分ける
    - **予定アクション**:
      - 榎木さんへ報告
    ### アクションアイテム
    | タイトル | 説明 | 責任者 | 期限 | 備考 |
    |:---|:---|:---|:---|:---|
    | 榎木さんへ報告 | 遅延を共有 | Speaker 1 | 未定 | |
    ### オープンクエスチョン
    - [???] リリース日はいつか
    """
    let summary = SummaryResponseParser.parse(document)
    if summary.decisions != ["SIDを分ける"] { report("fallback decisions: \(summary.decisions)") }
    if summary.openQuestions != ["リリース日はいつか"] { report("fallback questions: \(summary.openQuestions)") }
    if summary.actions.count != 1 || summary.actions.first?.owner != "Speaker 1" {
      report("fallback actions: \(summary.actions.map(\.title))")
    }
  }

  /// Only dates the meeting named become due dates; relative words stay unset.
  private static func checkSummaryActionDates() {
    let calendar = Calendar(identifier: .gregorian)
    guard let meeting = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)) else { return }
    func due(_ text: String) -> DateComponents? {
      SummaryActionItem(title: "x", due: text).dueDate(relativeTo: meeting, calendar: calendar)
        .map { calendar.dateComponents([.year, .month, .day], from: $0) }
    }
    if due("2026-10-09")?.day != 9 { report("ISO date not read") }
    if due("10月9日")?.month != 10 { report("Japanese date not read") }
    if due("1月20日")?.year != 2027 { report("date after new year not moved forward") }
    if due("来週") != nil || due("未定") != nil { report("relative or unknown due became a date") }
  }

  /// A generated document is drawn as blocks; a table becomes its rows.
  private static func checkSummaryDocumentBlocks() {
    let document = """
    # 見出し
    - **要点**:
      - 入れ子
    | タイトル | 責任者 |
    |:---|:---|
    | 報告 | Speaker 1 |
    ---
    """
    if !MarkdownBlockParser.hasBlockStructure(document) { report("structure not detected") }
    if MarkdownBlockParser.hasBlockStructure("短い要約です。\n- 箇条書きだけ") { report("plain text treated as document") }
    let blocks = MarkdownBlockParser.blocks(for: document)
    guard blocks.count == 5 else {
      report("block count \(blocks.count)")
      return
    }
    if case .bullet(let level, _, _) = blocks[2], level != 1 { report("nesting level \(level)") }

    let overviewDocument = """
    # 定例
    **日時**: 2026年9月15日  
    **会議の概要**:  
    **SID**を分ける方針で合意した。
    ---
    ## トピック1：SID
    """
    let preview = MarkdownBlockParser.overview(of: overviewDocument)
    if preview != "SIDを分ける方針で合意した。" { report("overview preview: \(preview)") }
    if case .table(let header, let rows) = blocks[3] {
      if header != ["タイトル", "責任者"] || rows != [["報告", "Speaker 1"]] { report("table \(header) \(rows)") }
    } else {
      report("table not parsed")
    }
  }

  private static func checkIconAssets() {
    for icon in MemoraIcon.allCases where UIImage(systemName: icon.systemName) == nil {
      report("icon missing: \(icon.rawValue)")
    }
  }

  /// Each provider needs its mark, a model to call, and the stored names that
  /// earlier builds wrote, so an existing choice and key carry over.
  private static func checkLLMProviders() {
    for provider in LLMProvider.allCases {
      if UIImage(named: provider.logoAssetName) == nil { report("logo missing: \(provider.rawValue)") }
      if provider.defaultModelID.isEmpty { report("no default model: \(provider.rawValue)") }
    }
    if LLMProvider(rawValue: "openAI") != .openAI || LLMProvider(rawValue: "anthropic") != .anthropic {
      report("legacy provider names")
    }
    if LLMProvider.openAI.keychainAccount != "ai.openAI" { report("legacy key account") }
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
  /// A week with nothing in it gets no review; a week with a meeting and a
  /// finished task names both, and a task due the following week is listed.
  private static func checkWeeklyReview() {
    let calendar = Calendar.current
    guard let week = calendar.dateInterval(of: .weekOfYear, for: Date(timeIntervalSince1970: 1_790_000_000)) else { return }
    let inWeek = week.start.addingTimeInterval(3600 * 30)
    let empty = WeeklyReviewBuilder.Input(week: week, meetings: [], tasks: [], entries: [], spaceNames: [:])
    if WeeklyReviewBuilder.markdown(empty) != nil {
      report("weekly review of an empty week")
    }

    let meeting = Meeting(
      id: UUID(), title: "定例会議", createdAt: inWeek, duration: 1800, source: .recording,
      status: .ready, summary: "進捗を確認した。", keyPoints: [], decisions: ["来週リリース"],
      openQuestions: [], transcript: [], spaceID: nil, audioURL: nil
    )
    let finished = MemoraTask(id: UUID(), title: "資料を送る", isCompleted: true, completedAt: inWeek)
    let upcoming = MemoraTask(id: UUID(), title: "見積もりを出す", dueDate: week.end.addingTimeInterval(3600 * 30), isCompleted: false)
    let input = WeeklyReviewBuilder.Input(week: week, meetings: [meeting], tasks: [finished, upcoming], entries: [], spaceNames: [:])
    let text = WeeklyReviewBuilder.markdown(input) ?? ""
    for expected in ["定例会議", "決定: 来週リリース", "資料を送る", "見積もりを出す"] where !text.contains(expected) {
      report("weekly review is missing \(expected)")
    }
  }

  /// 「田中さん」 should find 田中, without matching someone else.
  private static func checkPersonNames() {
    if !MemoraModel.isSameName("田中さん", "田中") || !MemoraModel.isSameName("山田 太郎", "山田太郎") {
      report("person names with honorifics or spaces")
    }
    if MemoraModel.isSameName("田中", "中田") {
      report("person names matched different people")
    }
  }

  /// Editing slides goes through their outline text, so reading it back must
  /// give the same headings, points and notes.
  private static func checkSlideOutline() {
    let slides = [
      DocumentSlide(title: "表紙", bullets: []),
      DocumentSlide(title: "決まったこと", bullets: ["来週リリース", "予算は据え置き"], notes: "補足\n二行目")
    ]
    let parsed = DocumentSlide.slides(fromOutline: DocumentSlide.outline(of: slides))
    let same = parsed.map { [$0.title] + $0.bullets + [$0.notes] } == slides.map { [$0.title] + $0.bullets + [$0.notes] }
    if !same {
      report("slide outline round trip: \(parsed)")
    }
  }

  /// A .pptx is a ZIP package; the checksum must match the standard one or
  /// PowerPoint refuses the file, and every slide needs its own part.
  private static func checkPresentationPackage() {
    if ZipArchive.crc32(Data("123456789".utf8)) != 0xCBF4_3926 {
      report("zip crc32")
    }
    var document = MemoraDocument(title: "A & B", kind: .slides)
    document.slides = [DocumentSlide(title: "<一枚目>", bullets: ["x"]), DocumentSlide(title: "二枚目", bullets: [])]
    let data = PPTXWriter.data(for: document)
    let text = String(decoding: data, as: UTF8.self)
    if !text.contains("ppt/slides/slide2.xml") || !text.contains("&lt;一枚目&gt;") || data.prefix(2) != Data("PK".utf8) {
      report("presentation package parts")
    }
  }

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

  /// The day timeline orders records morning to night, groups nearby station
  /// passes into one movement, keeps all-day events apart, and shows an event
  /// with a recording as one row.
  private static func checkJournalTimeline() {
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: .now)
    func at(_ hour: Int, _ minute: Int = 0, dayOf: Date? = nil) -> Date {
      calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayOf ?? day)!
    }
    func entry(
      _ title: String,
      _ date: Date,
      origin: LifeLogOrigin = .manual,
      meetingID: UUID? = nil
    ) -> LifeLogEntry {
      LifeLogEntry(
        id: UUID(),
        createdAt: date,
        title: title,
        summary: "",
        source: .iphone,
        meetingID: meetingID,
        origin: origin
      )
    }

    // Morning to night ordering, whatever order the records arrive in.
    let records = [
      entry("夜", at(18)),
      entry("朝", at(8)),
      entry("昼", at(12))
    ]
    let ordered = JournalTimelineBuilder.build(day: day, entries: records, events: [], meetings: [])
    let titles = ordered.items.compactMap { item -> String? in
      if case .entry(let entry) = item { return entry.title }
      return nil
    }
    if titles != ["朝", "昼", "夜"] {
      report("journal timeline order: \(titles)")
    }

    // Station passes within an hour form one movement; a later one starts another.
    let passes = [
      entry("A駅", at(8, 0), origin: .stationPass),
      entry("B駅", at(8, 30), origin: .stationPass),
      entry("C駅", at(10, 30), origin: .stationPass)
    ]
    let movements = JournalTimelineBuilder.movements(from: passes)
    if movements.count != 2 || movements.first?.entries.count != 2 {
      report("journal movement grouping: \(movements.map(\.entries.count))")
    }

    // The "now" line is only on today, and sits at the current time.
    let withNow = JournalTimelineBuilder.build(
      day: day, entries: records, events: [], meetings: [], now: at(9)
    )
    let nowIndex = withNow.items.firstIndex { $0.id == "nowMarker" }
    let noonIndex = withNow.items.firstIndex { if case .entry(let e) = $0 { return e.title == "昼" }; return false }
    if nowIndex == nil || !(nowIndex! > 0) || !(nowIndex! < (noonIndex ?? 0)) {
      report("journal now marker position: \(String(describing: nowIndex))")
    }
    let past = JournalTimelineBuilder.build(
      day: calendar.date(byAdding: .day, value: -1, to: day)!,
      entries: records,
      events: [],
      meetings: [],
      now: at(9)
    )
    if past.items.contains(where: { $0.id == "nowMarker" }) {
      report("journal now marker appeared on a past day")
    }

    // An event with a recording is one row, and the recording's own line is gone.
    let meetingID = UUID()
    var meeting = Meeting(
      id: meetingID,
      title: "定例",
      createdAt: at(10, 5),
      duration: 60,
      source: .recording,
      status: .ready,
      summary: "",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: []
    )
    meeting.calendarEventID = "evt-1"
    let event = JournalCalendarEvent(
      eventIdentifier: "evt-1",
      start: at(10),
      end: at(11),
      title: "定例",
      isAllDay: false,
      calendarTitle: "仕事",
      calendarColor: nil,
      location: nil
    )
    let allDay = JournalCalendarEvent(
      eventIdentifier: "evt-2",
      start: day,
      end: day,
      title: "終日",
      isAllDay: true,
      calendarTitle: "仕事",
      calendarColor: nil,
      location: nil
    )
    let matched = JournalTimelineBuilder.build(
      day: day,
      entries: [entry("録音", at(10, 5), meetingID: meetingID), entry("メモ", at(9))],
      events: [event, allDay],
      meetings: [meeting]
    )
    let eventRows = matched.items.filter { if case .calendarEvent = $0 { return true }; return false }
    let recordingRows = matched.items.filter {
      if case .entry(let e) = $0 { return e.meetingID == meetingID }
      return false
    }
    if eventRows.count != 1 || !recordingRows.isEmpty {
      report("recording-matched event was not one row: events \(eventRows.count), records \(recordingRows.count)")
    }
    if let first = eventRows.first, case .calendarEvent(let resolved) = first, resolved.meetingID != meetingID {
      report("matched event did not carry the recording id")
    }
    if matched.allDayEvents.map(\.title) != ["終日"] {
      report("all-day events were not kept apart: \(matched.allDayEvents.map(\.title))")
    }
  }

  /// Ask AI reaches records by the words of the question; a Japanese question
  /// has no spaces, so it must be cut into pieces that can still be found. Kana
  /// pairs and stop words are not terms, or ranking would fire on particles.
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

    for stop in ["した", "です", "ます", "こと", "について"] where terms.contains(stop) {
      report("question words kept a stop word: \(stop)")
    }

    func isHiraganaPair(_ term: String) -> Bool {
      guard term.count == 2 else { return false }
      return term.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) }
    }
    let hiraganaOnly = MemoraModel.questionWords(in: "これはどうした")
    if hiraganaOnly.contains(where: isHiraganaPair) {
      report("question words kept a kana pair: \(hiraganaOnly)")
    }
  }

  /// A file-scope question sends the whole transcript when it fits, never leaks a
  /// record outside the range, and is trimmed to the engine's limit when it does
  /// not.
  private static func checkAIContextLimits() {
    let small = Meeting(
      id: UUID(),
      title: "商談",
      createdAt: .now,
      duration: 60,
      source: .recording,
      status: .ready,
      summary: "見積もりを確認",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: [
        TranscriptSegment(id: UUID(), speaker: "田中", speakerIsCertain: true, timestamp: 0, text: "最初の発言です"),
        TranscriptSegment(id: UUID(), speaker: "佐藤", speakerIsCertain: true, timestamp: 5, text: "二つ目の発言です")
      ]
    )
    let fileRequest = AIQuestionRequest(question: "最初の発言は？", scope: .file(small.id), attachment: nil)
    let fileContent = MemoraModel.requestContent(
      for: fileRequest,
      scopeLabel: "商談",
      allowedMeetings: [small],
      tasks: [],
      characterLimit: 6_000
    )
    for expected in ["[00:00] 田中: 最初の発言です", "[00:05] 佐藤: 二つ目の発言です"] {
      if !fileContent.context.contains(expected) {
        report("AI context missed the full transcript line: \(expected)")
      }
    }
    if fileContent.sources.map(\.meetingID) != [small.id] {
      report("AI sources outside the range: \(fileContent.sources.map(\.title))")
    }
    if fileContent.sources.first?.excerpts.count != 2 {
      report("AI source excerpts were not kept per line: \(fileContent.sources.first?.excerpts.count ?? 0)")
    }

    var longTranscript: [TranscriptSegment] = []
    for index in 0..<200 {
      longTranscript.append(
        TranscriptSegment(
          id: UUID(),
          speaker: "話者",
          speakerIsCertain: true,
          timestamp: TimeInterval(index) * 10,
          text: "発言\(index)" + String(repeating: "あ", count: 100)
        )
      )
    }
    var long = small
    long.transcript = longTranscript
    let longRequest = AIQuestionRequest(question: "発言199は？", scope: .file(long.id), attachment: nil)
    let longContent = MemoraModel.requestContent(
      for: longRequest,
      scopeLabel: "長い会議",
      allowedMeetings: [long],
      tasks: [],
      characterLimit: 1_000
    )
    if longContent.context.count > 2_000 {
      report("AI context was not trimmed: \(longContent.context.count) characters")
    }
    if longContent.context.contains("発言199") {
      report("AI context kept the far end of a long transcript past the limit")
    }

    // The on-device limit covers the whole context, not just the transcript.
    let onDeviceLimit = AIEngineService.defaultContextCharacterLimit
    let onDeviceContent = MemoraModel.requestContent(
      for: longRequest,
      scopeLabel: "長い会議",
      allowedMeetings: [long],
      tasks: [],
      characterLimit: onDeviceLimit
    )
    if onDeviceContent.context.count > onDeviceLimit {
      report("on-device context exceeded its limit: \(onDeviceContent.context.count)")
    }
    if AIAnswerFailure.contextTooLarge.message == AIAnswerFailure.engineNotReady.message {
      report("a context overflow is shown as the model not being ready")
    }

    // Attachment and history share the same budget as the records.
    let longHistory = String(repeating: "やりとり", count: 2_000)
    let budgeted = MemoraModel.requestContent(
      for: fileRequest,
      scopeLabel: "商談",
      allowedMeetings: [small],
      tasks: [],
      history: longHistory,
      characterLimit: 2_000
    )
    if budgeted.history.count > 2_000 {
      report("history was not trimmed to the budget: \(budgeted.history.count)")
    }
    if budgeted.contextNote == nil {
      report("a trimmed context was not reported")
    }
    if budgeted.context.count + budgeted.history.count > 2_000 {
      report("context and history together exceeded the budget")
    }

    // A trimmed history keeps the newest exchange, not the oldest.
    let thread = "利用者: 古い質問A\n回答: 古い回答A\n利用者: 直前の質問\n回答: 直前の回答"
    let lastExchange = "利用者: 直前の質問\n回答: 直前の回答"
    let keptHistory = MemoraModel.trailingHistory(thread, budget: lastExchange.count)
    if !keptHistory.contains("直前の質問") || !keptHistory.contains("直前の回答") {
      report("a trimmed history dropped the newest exchange: \(keptHistory)")
    }
    if keptHistory.contains("古い質問A") {
      report("a trimmed history kept the oldest exchange")
    }

    // A multi-line answer too large for the budget still keeps its question.
    let multiline = "利用者: 古い\n回答: 古い回答\n利用者: 最新の質問\n回答: 1行目\n折り返しの2行目\nさらに3行目"
    let trimmedMultiline = MemoraModel.trailingHistory(multiline, budget: 20)
    if !trimmedMultiline.contains("利用者: 最新の質問") {
      report("a large latest exchange lost its question: \(trimmedMultiline)")
    }
    if trimmedMultiline.contains("古い回答") {
      report("a large latest exchange kept older turns")
    }

    // A long attachment cannot take the records' share of the budget.
    let attachmentURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("memora-selfcheck-\(UUID().uuidString).txt")
    let attachmentText = String(repeating: "添付の本文。", count: 2_000)
    if (try? attachmentText.write(to: attachmentURL, atomically: true, encoding: .utf8)) != nil {
      let attachment = AIAttachment(id: UUID(), name: "長い資料.txt", url: attachmentURL)
      let attachedRequest = AIQuestionRequest(question: "発言199は？", scope: .file(long.id), attachment: attachment)
      let attachedLimit = 2_000
      let attachedContent = MemoraModel.requestContent(
        for: attachedRequest,
        scopeLabel: "長い会議",
        allowedMeetings: [long],
        tasks: [],
        characterLimit: attachedLimit
      )
      let recordsFloor = (attachedLimit - attachedRequest.effectiveQuestion.count) * 2 / 5
      if attachedContent.context.count < recordsFloor {
        report("a long attachment starved the records: \(attachedContent.context.count) < \(recordsFloor)")
      }
      try? FileManager.default.removeItem(at: attachmentURL)
    }

    // A wide range whose first record alone is over budget still carries that
    // record, trimmed, rather than sending nothing.
    let globalRequest = AIQuestionRequest(question: "発言199は？", scope: .global, attachment: nil)
    let globalContent = MemoraModel.requestContent(
      for: globalRequest,
      scopeLabel: "すべての会話",
      allowedMeetings: [long],
      tasks: [],
      characterLimit: 600
    )
    if globalContent.context.isEmpty {
      report("a wide range with one large record sent nothing")
    }
    if globalContent.context.count > 600 {
      report("a wide range exceeded its budget: \(globalContent.context.count)")
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

  /// A record whose inline photos have not been written yet must keep its bytes
  /// through a save, so nothing is lost while migration is pending; a successful
  /// migration writes the files and drops the bytes.
  private static func checkLegacyPhotoRetention() {
    let original = Meeting(
      id: UUID(),
      title: "移行前",
      createdAt: .now,
      duration: 1,
      source: .recording,
      status: .ready,
      summary: "",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: [],
      legacyPhotoData: [Data([0x01, 0x02, 0x03])]
    )

    do {
      let data = try JSONEncoder().encode([original])
      let decoded = try JSONDecoder().decode([Meeting].self, from: data)
      if decoded.first?.legacyPhotoData == nil {
        report("inline photo bytes were dropped on save")
      }
    } catch {
      report("legacy photo round trip failed: \(error)")
    }

    var migrated = original
    if !migrated.materializeLegacyPhotos() {
      report("a writable inline photo failed to migrate")
    }
    if migrated.legacyPhotoData != nil {
      report("migrated photo bytes were kept")
    }
    guard let name = migrated.photoFileNames?.first else {
      report("migrated photo was not given a file name")
      return
    }
    MediaFiles.deletePhoto(name)
  }

  /// A whole-library question must reach tasks that are not tied to a record,
  /// while a record or project range must not carry them.
  private static func checkUnassignedTaskScope() {
    let unassigned = MemoraTask(
      id: UUID(),
      title: "担当未定のタスク",
      meetingID: nil,
      assignee: nil,
      dueDate: nil,
      isCompleted: false
    )
    if MemoraModel.openTasks(in: .all, from: [unassigned], meetings: []).isEmpty {
      report("a library-wide question dropped an unassigned task")
    }
    if !MemoraModel.openTasks(in: .files, from: [unassigned], meetings: []).isEmpty {
      report("a record range carried an unassigned task")
    }
    if !MemoraModel.openTasks(in: .projects, from: [unassigned], meetings: []).isEmpty {
      report("a project range carried an unassigned task")
    }
  }

  /// A very large attachment must be read only up to a limit, and the cut must
  /// not make a Japanese text file look like it is not UTF-8.
  private static func checkAttachmentReadLimit() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("selfcheck-attachment-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    let body = String(repeating: "日本語のテキスト\n", count: 100_000)
    guard (try? body.write(to: url, atomically: true, encoding: .utf8)) != nil else {
      report("attachment self-check could not write a file")
      return
    }
    let attachment = AIAttachment(id: UUID(), name: url.lastPathComponent, url: url)
    switch AIAttachmentText.read(attachment) {
    case .text(let text):
      if !text.hasSuffix("（長いため先頭のみ送信しました）") {
        report("a long attachment was not shortened")
      }
    case .unsupported(let reason):
      report("a large UTF-8 attachment was refused: \(reason)")
    }
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

    guard let speechToken = coordinator.claim(.speechInput) else {
      report("voice input could not claim a free session")
      return
    }
    if coordinator.claim(.playback) != nil {
      report("playback claimed the session while voice input held it")
    }
    if coordinator.refusal(for: .playback) == nil {
      report("no reason given for a busy session")
    }
    // A token that never held the session does nothing.
    coordinator.release(AudioSessionCoordinator.Token(id: UUID(), use: .playback))
    if coordinator.claim(.playback) != nil {
      report("a token that did not hold the session released it")
    }

    let recordingToken = coordinator.takeRecordingSession()
    if coordinator.claim(.speechInput) != nil {
      report("voice input claimed the session during a recording")
    }
    // The old voice-input token must not be able to end the recording.
    coordinator.release(speechToken)
    if !coordinator.isRecording {
      report("a stray release ended a recording")
    }
    coordinator.endRecording(recordingToken)
    if coordinator.isRecording {
      report("the recording claim was not released")
    }
    guard let playbackToken = coordinator.claim(.playback) else {
      report("playback could not claim the session after a recording")
      return
    }
    coordinator.release(playbackToken)
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

  /// Recording must ask the other users of the session to stop and wait for it
  /// before it takes the session.
  private static func runRecordingStopOrderCheck() async {
    let failuresBefore = failures
    let coordinator = AudioSessionCoordinator()
    var stoppedBeforeClaim = false
    coordinator.registerStopper(.playback) { stoppedBeforeClaim = true }
    let token = await coordinator.beginRecording()
    if !stoppedBeforeClaim {
      report("recording took the session before stopping the other user")
    }
    coordinator.endRecording(token)
    let passed = failures == failuresBefore
    guard let index = results.firstIndex(where: { $0.name == "Recording stop order" }) else { return }
    results[index].passed = passed
    results[index].detail = passed ? nil : lastDetail
  }
}
#endif
