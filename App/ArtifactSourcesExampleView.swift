#if DEBUG
import SwiftUI

struct ArtifactSourcesExampleView: View {
  @State private var showsExplanation = false
  private var rows: [ArtifactSourceRow] {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    return [
      .init(target: .record(.person(id)), title: "田中さん（架空の人物）", hasChanged: false, allowsCloudAI: true, canOpen: true),
      .init(target: .record(.task(id)), title: "次回の打ち合わせまでに提案内容と見積もりを確認する", hasChanged: true, allowsCloudAI: false, canOpen: true),
      .init(target: .record(.journal(id)), title: "前回の相談メモ", allowsCloudAI: false, canOpen: true),
      .init(target: .record(.meeting(id)), title: "企画の打ち合わせ", hasChanged: true, allowsCloudAI: true, canOpen: true),
      .init(target: .projectFile(id), title: "資料", allowsCloudAI: false, canOpen: false)
    ]
  }
  var body: some View {
    let sources = rows
    MemoraList {
      Section("本文の出典リンク") {
        InlineCitationExampleView()
      }
      Section {
        ForEach(sources) { row in
          ArtifactSourceLink(row: row) { showsExplanation = true }
        }
      } header: { Text("参照した情報") } footer: {
        Text("すべて架空データです。実際の記録の参照・保存・外部送信は行いません。")
      }
    }
    .navigationTitle("出典表示").navigationBarTitleDisplayMode(.inline)
    .alert("表示の確認", isPresented: $showsExplanation) { Button("閉じる", role: .cancel) {} } message: {
      Text("実際の資料・メールでは、選んだ元の情報を開きます。")
    }
  }
}
#endif
