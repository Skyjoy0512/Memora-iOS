import SwiftUI

/// Verifies the number by phone: the calling provider rings it, and the person
/// types the shown code on the call's keypad. No one needs to talk.
struct PhoneVerificationView: View {
  @Environment(MemoraModel.self) private var model
  var phoneNumber: String
  var onVerified: () -> Void

  @State private var verification: CallerVerification?
  @State private var isStarting = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 20) {
      if let verification {
        steps(verification)
      } else {
        Spacer()
        badge
        Text("電話番号を確認")
          .font(.title.bold())
        Text("確認のために誰かと話す必要はありません。")
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Spacer()

        if let errorMessage {
          Label(errorMessage, icon: .exclamationmarkTriangle)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        Text(PhoneNumberFormat.display(phoneNumber))
          .font(.title3.monospacedDigit())
        Text("この番号に電話をかけて確認します")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Button(action: start) {
          Group {
            if isStarting {
              ProgressView().tint(.black)
            } else {
              Image(icon: .phoneFill).font(.title2)
            }
          }
          .foregroundStyle(.black)
          .frame(width: 200, height: 58)
          .background(.green, in: Capsule())
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isStarting)
        .accessibilityLabel("確認の電話を受ける")
        .padding(.bottom, 16)
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity)
    .background(Color(uiColor: .systemGroupedBackground))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var badge: some View {
    Image(icon: .checkmarkSealFill)
      .font(.system(size: 44))
      .foregroundStyle(.white)
      .frame(width: 96, height: 96)
      .background(.green, in: Circle())
      .accessibilityHidden(true)
  }

  private func steps(_ verification: CallerVerification) -> some View {
    VStack(spacing: 18) {
      Text("確認の手順")
        .font(.title2.bold())
      Label("電話をかけています…", icon: .phone)
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())

      VStack(spacing: 0) {
        stepRow(1, "次の番号からの電話に出ます", detail: PhoneNumberFormat.display(verification.callingFrom))
        Divider()
        stepRow(2, "通話画面を全画面にします", detail: nil)
        Divider()
        stepRow(3, "通話中にキーパッドを開きます", detail: nil)
        Divider()
        stepRow(4, "次の6桁を入力します", detail: verification.code, isCode: true)
      }
      .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

      Spacer()
    }
    .task { await waitForVerification() }
  }

  private func stepRow(_ number: Int, _ title: String, detail: String?, isCode: Bool = false) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Text("\(number)")
        .font(.headline)
        .frame(width: 32, height: 32)
        .background(Color.primary.opacity(0.08), in: Circle())
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
        if let detail {
          Text(detail)
            .font(isCode ? .title.monospacedDigit().bold() : .title3.monospacedDigit())
            .tracking(isCode ? 6 : 0)
            .textSelection(.enabled)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(16)
  }

  private func start() {
    isStarting = true
    errorMessage = nil
    Task {
      do {
        verification = try await model.callingService.startCallerVerification(phoneNumber: phoneNumber)
      } catch {
        errorMessage = error.localizedDescription
      }
      isStarting = false
    }
  }

  /// Checks every few seconds until the provider reports the code was entered.
  private func waitForVerification() async {
    for _ in 0..<60 {
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      if (try? await model.callingService.isVerified(phoneNumber: phoneNumber)) == true {
        onVerified()
        return
      }
    }
    errorMessage = CallingError.verificationFailed.localizedDescription
    verification = nil
  }
}
