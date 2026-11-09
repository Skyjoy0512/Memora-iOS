#!/usr/bin/env python3
"""Exercise question confirmation and structured exports without providers or app data."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
source = (ROOT / "App/AgentQuestionCard.swift").read_text()
methods = source[source.index("  private var hasAnswer:"):source.rfind("\n}")]
setter = source[source.index("            custom[questionIndex] = value"):source.index("\n          }\n        ))", source.index("            custom[questionIndex] = value"))]
fixture = r'''import Foundation
@MainActor final class AnswerSink {
 var answers: [String]?
 func resolveAgentQuestions(_ answers: [String]?, requestID: UUID) { self.answers = answers }
}
@MainActor final class QuestionProbe {
 var request = AgentQuestionRequest(messageID: UUID(), questions: [.init(text: "確認", allowsMultiple: false, options: ["候補"])])
 var index = 0
 var picked: [Int: Set<Int>] = [:]
 var custom: [Int: String] = [:]
 var movingForward = true
 var questions: [AgentQuestion] { request.questions }
 var isLast: Bool { index == questions.count - 1 }
 var model = AnswerSink()
 func select() { choose(0, in: questions[0]) }
 func confirm() { advance() }
 func skipCurrent() { skip() }
 func enter(_ value: String) { let questionIndex = index, question = questions[index]
''' + setter + "\n }\n" + methods + "\n}\n" + r'''
@main struct UIInteractionChecks {
 @MainActor static func main() async throws {
   let question = QuestionProbe()
   question.select()
   question.enter("入力を続けています")
   try await Task.sleep(for: .milliseconds(600))
   precondition(question.model.answers == nil, "Choosing and typing must never submit automatically")
   question.confirm()
   precondition(question.model.answers == ["入力を続けています"])
   let skipped = QuestionProbe()
   skipped.select()
   skipped.skipCurrent()
   precondition(skipped.model.answers == [""])
   let json = #"{"version":1,"components":[{"id":"table","kind":"ComparisonTable","columns":["対象","値"],"items":[{"id":"row","cells":["予算","150万円"]}]},{"id":"timeline","kind":"Timeline","items":[{"id":"event","title":"締切","detail":"12月20日"}]}]}"#
   let text = "比較結果\n\n```memora-ui\n" + json + "\n```"
   let exported = NativeAIInterface.exportMarkdown(text)
   precondition(exported.contains("| 予算 | 150万円 |") && exported.contains("12月20日"))
   precondition(!exported.contains("memora-ui"))
   let escapedTable = NativeAIInterface.exportMarkdown(text.replacingOccurrences(of: "150万円", with: "A|B"))
   precondition(escapedTable.contains(#"A\|B"#))
   let id = UUID()
   let refs = "```memora-ui\n" + #"{"version":1,"components":[{"id":"task","kind":"TaskList","items":[{"id":"task1","referenceID":""# + id.uuidString + #"","title":"model supplied private title"}]}]}"# + "\n```"
   precondition(!NativeAIInterface.exportMarkdown(refs).contains("model supplied"))
   precondition(NativeAIInterface.exportMarkdown(refs) { _, ids in ids == [id] ? ["許可された実際のタスク"] : nil }.contains("許可された実際のタスク"))
   var selection = NoteAttachmentSelection()
   let a = UUID(), b = UUID()
   selection.toggle(a, maximumCount: 1); selection.toggle(b, maximumCount: 1)
   precondition(selection.ids == [a])
   selection.toggle(a, maximumCount: 0)
   precondition(selection.isEmpty)
   print("PASS: explicit question submission, unfinished input retained, structured table/timeline export, reference denial/resolution, attachment capacity, editor failure/retry and escaped table cells")
 }
}
'''
inline = (ROOT / "App/InlineMarkdownEditor.swift").read_text()
commit = inline[inline.index("  private func commit("):inline.index("  /// Saves what is being typed")]
fixture = fixture.replace("@main struct UIInteractionChecks", r'''@MainActor enum DraftStore {
 static var values: [String: String] = [:]
 static func clear(_ key: String, matching value: String) { if values[key] == value { values[key] = nil } }
}
@MainActor final class SaveProbe {
 var isSaving = false
 var saveFailed = false
 var retainedDraft: String? = "未保存の内容"
 var draftSessionID = UUID()
 var commitTask: Task<Void, Never>?
 var onCommit: (String) async -> Bool = { _ in false }
 func retry() { commit(retainedDraft!, key: "editor", session: draftSessionID) }
''' + commit + "\n}\n@main struct UIInteractionChecks")
fixture = fixture.replace("   let question = QuestionProbe()", r'''   let save = SaveProbe()
   DraftStore.values["editor"] = save.retainedDraft
   save.retry()
   await save.commitTask?.value
   precondition(save.saveFailed && !save.isSaving && save.retainedDraft != nil && DraftStore.values["editor"] != nil)
   save.onCommit = { _ in true }
   save.retry()
   await save.commitTask?.value
   precondition(!save.saveFailed && save.retainedDraft == nil && DraftStore.values["editor"] == nil)
   let question = QuestionProbe()''')
with tempfile.TemporaryDirectory(prefix="memora-ui-interaction-", dir=os.environ.get("MEMORA_CHECK_ROOT")) as temp:
    folder = Path(temp)
    swift = folder / "UIInteractionChecks.swift"
    swift.write_text(fixture)
    binary = folder / "checks"
    subprocess.run(["swiftc", "-swift-version", "6", "App/AgentQuestion.swift", "App/AgentQuestionRequest.swift", "App/ToolInputValidator.swift", "App/NativeAIInterface.swift", "App/NativeAIComponentStream.swift", "App/NoteAttachmentSelection.swift", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=15)
