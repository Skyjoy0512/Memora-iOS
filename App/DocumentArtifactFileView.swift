import SwiftUI

struct DocumentArtifactFileView: View {
  var document: MemoraDocument
  var url: URL
  var preview: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { actions }
        VStack(alignment: .leading, spacing: 8) { actions }
      }
      if document.hasOutdatedArtifact {
        Text(document.companyTemplateID == nil
          ? "本文の変更は保存済みです。共有メニューのWord・PowerPointは最新の本文から作成します。"
          : "本文の変更は保存済みですが、会社ファイルには反映されていません。元の書式と編集前のファイルを保持しています。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.borderless)
  }

  @ViewBuilder private var actions: some View {
    Button(document.hasOutdatedArtifact ? "編集前のファイルを確認" : "生成ファイルを確認", icon: .docText, action: preview)
      .frame(minHeight: MemoraSpacing.touchTarget)
    ShareLink(item: url) {
      Label(document.hasOutdatedArtifact ? "編集前のファイルを共有" : "保存・共有", icon: .squareAndArrowUp)
        .frame(minHeight: MemoraSpacing.touchTarget)
    }
  }
}
