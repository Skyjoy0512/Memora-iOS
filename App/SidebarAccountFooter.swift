import SwiftUI

/// Account actions stay anchored while workspace destinations scroll above.
struct SidebarAccountFooter: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  var profile: UserProfile
  var displayName: String
  var accountStatus: String
  var isSignedIn: Bool
  var onAccount: () -> Void
  var onPlan: () -> Void
  var onSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      Divider().accessibilityHidden(true)
      Button(action: onAccount) {
        HStack(spacing: MemoraSpacing.md) {
          ProfileAvatar(profile: profile, size: 32)
          VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
            Text(displayName).font(MemoraTypography.body.weight(.medium))
            Group {
              if typeSize.isAccessibilitySize, !isSignedIn {
                Text("サインイン")
              } else {
                Text(accountStatus)
              }
            }
            .font(MemoraTypography.metadata)
            .foregroundStyle(MemoraPalette.textSecondary)
          }
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
        .contentShape(Rectangle())
      }
      .accessibilityLabel(isSignedIn ? "アカウント \(displayName)" : "サインイン")

      HStack(spacing: MemoraSpacing.md) {
        Button(action: onPlan) {
          HStack(spacing: MemoraSpacing.sm) {
            MemoraInterfaceIcon(icon: .crown)
            Group {
              if typeSize.isAccessibilitySize {
                Text("プラン")
              } else {
                Text("Memora Plus")
              }
            }
            .font(MemoraTypography.secondary.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
          }
          .frame(minHeight: MemoraSpacing.touchTarget)
          .contentShape(Rectangle())
        }
        .accessibilityLabel("Memora Plus、プランと利用状況")
        Spacer(minLength: 0)
        Button(action: onSettings) {
          Label("設定", icon: .gearshape)
            .labelStyle(.iconOnly)
            .font(.system(size: MemoraIconMetrics.glyph, weight: .regular))
            .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
            .contentShape(Circle())
            .memoraGlass(in: Circle(), interactive: true)
        }
        .accessibilityHint("プロフィールと設定を開きます")
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(MemoraPalette.textPrimary)
    .padding(.horizontal, MemoraSpacing.screen)
    .padding(.top, MemoraSpacing.sm)
    .padding(.bottom, MemoraSpacing.md)
  }
}
