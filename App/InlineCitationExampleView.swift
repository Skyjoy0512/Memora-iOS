#if DEBUG
import SwiftUI

struct InlineCitationExampleView: View {
  @State private var openedType: String?

  var body: some View {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let targets: Set<ArtifactSourceTarget> = [.record(.person(id)), .record(.task(id)), .record(.journal(id))]
    let source = "田中さんとの確認事項 " + AnswerSourceCitation.marker(for: .record(.person(id)))
      + "\n\n提案内容と見積もりを確認します。 " + AnswerSourceCitation.marker(for: .record(.task(id)))
      + "\n\n前回の相談メモを参照しています。 " + AnswerSourceCitation.marker(for: .record(.journal(id)))
    AIResponseText(text: AnswerCitations.linked(source, sources: [], allowedTargets: targets))
      .environment(\.openURL, OpenURLAction { url in
        guard let target = AnswerSourceCitation.target(for: url), targets.contains(target) else { return .discarded }
        openedType = target.label
        return .handled
      })
      .alert("出典リンク", isPresented: Binding(get: { openedType != nil }, set: { if !$0 { openedType = nil } })) {
        Button("閉じる", role: .cancel) { openedType = nil }
      } message: {
        Text("選んだ出典: \(openedType ?? "")。架空データの表示確認です。")
      }
  }
}
#endif
