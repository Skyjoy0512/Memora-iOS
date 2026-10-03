import SwiftUI

/// The number is verified; calls can be placed.
struct CallVerifiedView: View {
  var onContinue: () -> Void

  var body: some View {
    VStack(spacing: 18) {
      Spacer()
      Image(icon: .checkmarkSealFill)
        .font(.system(size: 44))
        .foregroundStyle(.white)
        .frame(width: 96, height: 96)
        .background(.green, in: Circle())
        .accessibilityHidden(true)
      Text("確認できました")
        .font(.title.bold())
      Text("電話番号を確認しました。\nMemoraから電話をかけられます。")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Spacer()
      CallPrimaryButton(title: "続ける", action: onContinue)
    }
    .padding(24)
    .background(Color(uiColor: .systemGroupedBackground))
    .navigationBarBackButtonHidden(true)
    .navigationBarTitleDisplayMode(.inline)
  }
}
