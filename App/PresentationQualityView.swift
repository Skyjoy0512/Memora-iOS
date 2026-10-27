import SwiftUI

struct PresentationQualityView: View {
  var document: MemoraDocument

  var body: some View {
    let issues = PresentationValidator.issues(for: document)
    DisclosureGroup("品質チェック（\(issues.count)件）") {
      VStack(alignment: .leading, spacing: MemoraSpacing.md) {
        Text("版面・入力・同じ出典の数値を機械検査しています。数値の真偽、日本語の自然さ、論理の妥当性は原資料と照合してください。")
          .foregroundStyle(.secondary)
        if issues.isEmpty { Text("機械検査の指摘はありません。") }
        ForEach(issues) { issue in
          let page = document.slides.firstIndex { $0.id == issue.slideID }.map { $0 + 1 }
          Text((page.map { "\($0)枚目: " } ?? "") + issue.message)
            .foregroundStyle(issue.isError ? AnyShapeStyle(MemoraPalette.danger) : AnyShapeStyle(.secondary))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, MemoraSpacing.sm)
    }
    .font(.footnote)
  }
}
