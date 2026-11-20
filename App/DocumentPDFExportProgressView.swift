import SwiftUI

struct DocumentPDFExportProgressView: View {
  var progress: DocumentPDFProgress
  var cancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
      Text("PDFを書き出しています").font(.headline)
      switch progress {
      case .preparing:
        ProgressView("ページを組んでいます…")
      case .writing(let completed, let total):
        ProgressView(value: Double(completed), total: Double(max(1, total))) {
          Text("\(completed) / \(total)ページを作成")
        }
      }
      Button("キャンセル", role: .cancel, action: cancel)
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
    .padding(24)
    .frame(maxWidth: 360, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    .padding(20)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityIdentifier("document.pdf.progress")
  }
}
