import SwiftUI

struct DocumentArtifactFileView: View {
  var document: MemoraDocument
  var url: URL
  var preview: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      if document.hasOutdatedArtifact {
        Text(document.companyTemplateID == nil
          ? "ここでは編集前のファイルを開けます。上の共有メニューから、最新の内容を書き出せます。"
          : "ここでは編集前の会社ファイルを開けます。最新の内容を共有するには、上の共有メニューでテキストを選んでください。")
          .font(MemoraTypography.secondary)
          .foregroundStyle(MemoraPalette.textSecondary)
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: MemoraSpacing.lg) { actions }
        VStack(alignment: .leading, spacing: MemoraSpacing.sm) { actions }
      }
    }
    .buttonStyle(.borderless)
  }

  @ViewBuilder private var actions: some View {
    Button(document.hasOutdatedArtifact ? "編集前のファイルを開く" : "生成ファイルを開く", icon: .docText, action: preview)
      .frame(minHeight: MemoraSpacing.touchTarget)
    ShareLink(item: url) {
      Label(document.hasOutdatedArtifact ? "編集前のファイルを共有" : "生成ファイルを共有", icon: .squareAndArrowUp)
        .frame(minHeight: MemoraSpacing.touchTarget)
    }
  }
}
