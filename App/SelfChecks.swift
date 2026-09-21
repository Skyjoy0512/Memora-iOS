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
    checkPhotoThumbnailNaming()
    checkStatusFilter()
  }

  /// A summary must not be applied to a transcript that changed while it was
  /// being written, so the fingerprint has to notice an edit.
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
