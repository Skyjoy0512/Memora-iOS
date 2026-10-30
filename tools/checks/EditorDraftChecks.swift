import Foundation

@main struct EditorDraftChecks {
  static func main() throws {
    let baseline = ["title": "会議", "body": "変更前\n本文"]
    let changed = ["title": "会議", "body": "編集中\n日本語\"引用\""]
    let draft = EditorDraftEnvelope(baseline: baseline, values: changed)
    let reopened = try JSONDecoder().decode(EditorDraftEnvelope.self, from: JSONEncoder().encode(draft))
    precondition(reopened.restored(matching: baseline) == changed)
    precondition(reopened.restored(matching: ["title": "会議", "body": "別の画面で保存済み"]) == nil)
    precondition(reopened.restored(matching: [:]) == nil)
    precondition(EditorDraftEnvelope(baseline: baseline, values: ["title": "不完全"]).restored(matching: baseline) == nil)
    print("EditorDraftChecks passed: reopen restores Japanese text, changed original and incompatible field sets refuse stale drafts")
  }
}
