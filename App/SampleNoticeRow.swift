import SwiftUI

/// Shown at the top of the files and journal lists while any display sample is
/// present, with the one action that clears them. The removal is confirmed and
/// takes only the samples, never the person's own records.
struct SampleNoticeRow: View {
  @Environment(MemoraModel.self) private var model
  @State private var isConfirming = false

  var body: some View {
    HStack(spacing: 10) {
      Image(icon: .sparkles)
        .foregroundStyle(.primary)

      Text("サンプルを表示しています")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Spacer(minLength: 8)

      Button("サンプルを削除") {
        isConfirming = true
      }
      .font(.subheadline.weight(.semibold))
    }
    .padding(14)
    .memoraCard(radius: 16)
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
