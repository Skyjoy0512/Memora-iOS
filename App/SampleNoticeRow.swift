import SwiftUI

/// Shown at the top of the files and journal lists while any display sample is
/// present, with the one action that clears them. The removal is confirmed and
/// takes only the samples, never the person's own records.
struct SampleNoticeRow: View {
  @Environment(MemoraModel.self) private var model
  @State private var isConfirming = false
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.md))
      : AnyLayout(HStackLayout(spacing: MemoraSpacing.sm))
    return layout {
      HStack(spacing: MemoraSpacing.sm) {
        Image(icon: .sparkles)
          .foregroundStyle(.primary)
          .accessibilityHidden(true)

        Text("サンプル表示中")
          .font(MemoraTypography.metadata)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

      }
      if !typeSize.isAccessibilitySize { Spacer(minLength: MemoraSpacing.sm) }

      Button { isConfirming = true } label: {
        Text("削除")
          .font(.subheadline.weight(.medium))
          .fixedSize(horizontal: false, vertical: true)
          .frame(minWidth: MemoraSpacing.touchTarget, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("サンプルを削除")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MemoraSpacing.md)
    .memoraCard()
    .confirmationDialog("サンプルを削除しますか？", isPresented: $isConfirming, titleVisibility: .visible) {
      Button("削除", role: .destructive) {
        model.deleteSampleContent()
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("表示用のサンプルだけを削除します。録音した記録には触れません。サンプルの会議に追加したタスクも削除されます。")
    }
  }
}
