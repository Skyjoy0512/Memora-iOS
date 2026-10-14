#if DEBUG
import SwiftUI

struct AgentTaskDraftExampleView: View {
  @State private var drafts: [AgentTaskDraft] = [
    AgentTaskDraft(title: "見積書の内容を確認する", detail: "表示検証用の例です。実際の記録ではありません。"),
    AgentTaskDraft(title: "次回の打ち合わせに向けて未決事項を整理する")
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("表示と編集の検証用です。タスク登録・外部送信・AI呼び出しは行いません。")
          .font(.footnote).foregroundStyle(.secondary)
        AgentTaskDraftList(drafts: drafts) { draft in
          if let index = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[index] = draft }
        }
        Text("選択 \(drafts.filter(\.isSelected).count)件").font(.footnote).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
    }
    .background(MemoraPalette.background)
    .navigationTitle("タスク候補の表示確認").navigationBarTitleDisplayMode(.inline)
  }
}
#endif
