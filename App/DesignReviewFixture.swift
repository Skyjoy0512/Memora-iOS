#if DEBUG
import Foundation

@MainActor enum DesignReviewFixture {
  static let recordID = UUID(uuidString: "1AFAB0D2-BEEA-4C73-8452-F159D40F1F01")!
  static let markdown = """
  # 次の一歩をそろえる

  これは表示と編集を確認するための架空の要約です。外部APIは使用していません。

  ## 今回の合意

  日本語の長い文章を、段落・見出し・余白で読み進められるようにします。数値や担当者が記録にないときは補わず、確認が必要な点を明確に分けます。スマートフォンでも大きな文字でも、読み手が今どこを読んでいるかを見失わないことを重視します。

  - 記録の本文を確認する
  - 長い箇条書きが折り返されるときも、本文の開始位置をそろえます。見出しと補足を区別しながら、保存された内容を省略せず表示します。
    - 未確認の条件は次回の相談で確かめる

  > 担当と期限は、記録で確認できた内容だけを記載します。

  | 項目 | 内容 | 状態 |
  | --- | --- | --- |
  | 読みやすさ | 日本語の本文と編集欄で同じ文字組みを使う | 確認中 |
  | 操作 | 元の記録と出典を開けるようにする | 確認中 |

  ## 次回の確認

  保存後に画面を開き直し、編集した段落が残っていることを確認します。表示モードを切り替えても、データの形式や出典が変わることはありません。

  ```swift
  let title = "確認用の架空資料"
  print(title)
  ```
  """

  static func prepare(in model: MemoraModel) -> Bool {
    guard model.currentTeamID == nil, !model.isRestoring, !model.isStoreProtected else { return false }
    if model.meeting(id: recordID) != nil { return true }
    let record = Meeting(id: recordID, title: "QA デザイン検証の要約", createdAt: .now, duration: 0,
      source: .importFile, status: .ready, summary: markdown, keyPoints: [], decisions: [], openQuestions: [], transcript: [], spaceID: nil)
    let candidate = [record] + model.meetings
    guard model.persistNow(candidate, forKey: MemoraModel.StorageKey.meetings) else { return false }
    model.meetings = candidate
    return true
  }

  static func verify(in model: MemoraModel) -> String {
    guard let current = model.meeting(id: recordID),
          case .data(let data) = RecordStore.load(MemoraModel.StorageKey.meetings),
          let records = try? JSONDecoder().decode([Meeting].self, from: data),
          records.first(where: { $0.id == recordID })?.summary == current.summary else { return "SQLiteの一致を確認できませんでした" }
    return "SQLite再読込一致：" + (current.summary.contains("E2E保存確認") ? "編集内容を保存済み" : "原文を保存済み")
  }

  static func cleanup(in model: MemoraModel) -> Bool {
    guard model.currentTeamID == nil, !model.isRestoring, !model.isStoreProtected else { return false }
    let candidate = model.meetings.filter { $0.id != recordID }
    guard model.persistNow(candidate, forKey: MemoraModel.StorageKey.meetings) else { return false }
    model.meetings = candidate
    DraftStore.clear("meeting.\(recordID).summary")
    return true
  }
}
#endif
