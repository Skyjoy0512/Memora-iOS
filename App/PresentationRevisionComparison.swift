import SwiftUI

struct PresentationRevisionComparison: View {
  var revision: PresentationRevision

  var body: some View {
    ForEach(revision.replacements) { slide in
      Section(slide.title.isEmpty ? "修正案" : slide.title) {
        if let original = revision.originals.first(where: { $0.id == slide.id }) {
          DisclosureGroup("変更前") {
            DocumentSlidesView(document: MemoraDocument(title: "変更前", kind: .slides, slides: [original]))
          }
        }
        DocumentSlidesView(document: MemoraDocument(title: "修正案", kind: .slides, slides: [slide]))
        let issues = PresentationValidator.issues(for: slide)
        ForEach(issues) { issue in
          Text(issue.message).font(.footnote)
            .foregroundStyle(issue.isError ? AnyShapeStyle(MemoraPalette.danger) : AnyShapeStyle(.secondary))
        }
        Text("数値と出典の保持検査は通過。文言の意味・条件は確認が必要です。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
