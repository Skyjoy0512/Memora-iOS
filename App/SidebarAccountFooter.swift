import SwiftUI

struct SidebarAccountFooter: View {
  var onSettings: () -> Void

  var body: some View {
    HStack {
      Spacer(minLength: 0)
      Button(action: onSettings) {
        Label("設定", icon: .gearshape)
          .labelStyle(.iconOnly)
          .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
          .contentShape(Circle())
          .memoraGlass(in: Circle(), interactive: true)
      }
      .accessibilityHint("プロフィールと設定を開きます")
      .accessibilityIdentifier("sidebar.settings")
    }
    .buttonStyle(.plain)
    .foregroundStyle(MemoraPalette.textPrimary)
    .padding(.horizontal, MemoraSpacing.screen)
    .padding(.top, MemoraSpacing.sm)
    .padding(.bottom, MemoraSpacing.md)
  }
}
