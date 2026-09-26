import SwiftUI

/// The top-right way into Settings on every tab, drawn as the person's own
/// picture so it reads as "me and my settings".
struct SettingsToolbarButton: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    Button {
      model.isSettingsPresented = true
    } label: {
      Label {
        Text("設定")
      } icon: {
        ProfileAvatar(profile: model.profile, size: 30)
      }
      .labelStyle(.iconOnly)
    }
    .accessibilityLabel("設定")
    .accessibilityHint("プロフィールと設定を開きます")
  }
}
