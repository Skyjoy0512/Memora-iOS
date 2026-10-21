import Contacts
import SwiftUI

/// Lets the dialer list the person's contacts. They are read on the device
/// only; Memora's servers never see them.
struct ConnectContactsView: View {
  var onFinish: () -> Void
  @State private var isDenied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Spacer()
      Image(icon: .personCropCircleBadgePlus, size: 40)
        .font(.system(size: 40))
        .foregroundStyle(.tint)
        .frame(width: 84, height: 84)
        .background(Color.accentColor.opacity(0.12), in: Circle())
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)

      Text("連絡先をつなぐ")
        .font(.largeTitle.bold())
      Text("連絡先の人にMemoraから電話をかけるには、連絡先をつなぎます。")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 8) {
        Label("連絡先はこのiPhoneに残り、Memoraのサーバーには送りません。", icon: .lock)
        Label("通話した相手は、記録の「人物」とひもづけられます。", icon: .person2)
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)

      if isDenied {
        Text("連絡先へのアクセスがオフです。設定アプリのMemoraから許可できます。キーパッドからはいつでもかけられます。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Spacer()

      CallPrimaryButton(title: "連絡先をつなぐ", icon: .personCropCircleBadgePlus) {
        Task { await connect() }
      }
      Button("スキップ", action: onFinish)
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .padding(MemoraSpacing.xxl)
    .background(MemoraPalette.background)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func connect() async {
    let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
    if granted {
      onFinish()
    } else {
      isDenied = true
    }
  }
}
