import SwiftUI

/// The same settings action on every tab; profile editing lives in Settings.
struct SettingsToolbarButton: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    Button("設定", icon: .gearshape) {
      model.isSettingsPresented = true
    }
    .labelStyle(.iconOnly)
    .accessibilityLabel("設定")
    .accessibilityHint("プロフィールと設定を開きます")
  }
}
