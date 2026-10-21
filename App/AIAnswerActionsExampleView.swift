#if DEBUG
import SwiftUI

/// Exercises the production action bar with local callbacks, never tools or real speech.
struct AIAnswerActionsExampleView: View {
  @State private var allowsRetry = true
  @State private var saves = 0
  @State private var retries = 0
  @State private var reads = 0
  @State private var speaking = false
  @State private var skillDraft: MemoraSkill?

  var body: some View {
    MemoraForm {
      Section {
        Text("架空の回答です。資料保存・再試行・読み上げは件数の確認だけです。スキル作成は実際の編集画面を開き、「保存」を押すと端末に手順を保存します。外部APIは使いません。")
          .font(.footnote).foregroundStyle(.secondary)
        Toggle("再試行可能として表示", isOn: $allowsRetry)
      }
      Section("架空の回答") {
        Text(Self.answer).textSelection(.enabled)
        AIResponseActionBar(text: Self.answer, canRetry: allowsRetry,
          isSpeaking: speaking, readAloud: { reads += 1; speaking.toggle() },
          save: { saves += 1 }, retry: { retries += 1 },
          saveSkill: { skillDraft = .draft(instructions: Self.answer) })
      }
      Section("確認結果") {
        LabeledContent("保存の操作", value: saves.formatted())
        LabeledContent("再試行の操作", value: retries.formatted())
        LabeledContent("読み上げの操作", value: reads.formatted())
      }
    }
    .navigationTitle("回答アクションの確認").navigationBarTitleDisplayMode(.inline)
    .sheet(item: $skillDraft) { SkillEditorView(skill: $0, reviewsAnswer: true) }
  }

  private static let answer = """
  次回の相談では、提案の読者と判断してほしい点を確認します。

  費用と担当は未確認です。合意した内容と分けて記載してください。
  """
}
#endif
