import SwiftUI

/// How calling works, and the notice about recording consent, before anything
/// is set up.
struct CallExplanationView: View {
  var onContinue: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 24) {
          Image(icon: .phoneFill, size: 28)
            .foregroundStyle(.white)
            .frame(width: 72, height: 72)
            .background(.green, in: Circle())
            .accessibilityHidden(true)

          Text("Memoraで電話をかける")
            .font(.title.bold())
            .multilineTextAlignment(.center)

          VStack(alignment: .leading, spacing: 14) {
            step(.phone, "電話をかけて、あなたの番号を確認します")
            step(.personCropCircleBadgePlus, "そのあと、連絡先をつなげます")
          }
          .padding(MemoraSpacing.lg)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))

          VStack(alignment: .leading, spacing: 12) {
            Label("通話の録音には、相手への告知と同意が必要な場合があります。", icon: .bellFill)
              .font(.headline)
            Text("国や地域によっては、通話を録音する前に参加者へ知らせ、同意を得ることが法律で求められています。")
            Text("通話の冒頭で「記録のために録音します」と伝えるなど、要件を守るのは利用者の責任です。通話中はいつでも録音を一時停止できます。")
          }
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MemoraSpacing.xxl)
      }

      CallPrimaryButton(title: "はじめる", action: onContinue)
        .padding(.horizontal, MemoraSpacing.xxl)
        .padding(.bottom, MemoraSpacing.lg)
    }
    .background(MemoraPalette.background)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func step(_ icon: MemoraIcon, _ text: String) -> some View {
    HStack(spacing: 14) {
      Image(icon: icon, size: 17)
        .frame(width: 40, height: 40)
        .background(Color(uiColor: .systemBackground), in: Circle())
        .accessibilityHidden(true)
      Text(text)
        .font(.body)
    }
  }
}
