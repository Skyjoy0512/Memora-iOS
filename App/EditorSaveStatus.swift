import SwiftUI

struct EditorSaveStatus: View {
  var isSaving: Bool
  var hasFailure: Bool
  var retry: () -> Void

  var body: some View {
    if isSaving {
      ProgressView("保存しています…")
        .font(.footnote)
        .accessibilityIdentifier("editor.save.pending")
    } else if hasFailure {
      VStack(alignment: .leading, spacing: 4) {
        Label("変更はまだ保存されていません。内容を確認して再試行してください。", icon: .exclamationmarkTriangle)
          .font(.footnote).foregroundStyle(MemoraPalette.danger)
        Button("もう一度保存", action: retry)
          .frame(minHeight: 44)
      }
      .accessibilityIdentifier("editor.save.failed")
    }
  }
}
