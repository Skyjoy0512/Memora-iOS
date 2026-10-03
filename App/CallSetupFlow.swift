import SwiftUI

/// Setting up calls: what it is, recording consent, the person's number, a
/// verification call, and their contacts. Ends on the dialer.
struct CallSetupFlow: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var path: [CallSetupStep] = []

  var body: some View {
    NavigationStack(path: $path) {
      CallIntroView { path.append(.explanation) }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
          }
        }
        .navigationDestination(for: CallSetupStep.self) { step in
          switch step {
          case .explanation:
            CallExplanationView { path.append(.phoneNumber) }
          case .phoneNumber:
            PhoneNumberEntryView { number in path.append(.verification(number)) }
          case .verification(let number):
            PhoneVerificationView(phoneNumber: number) {
              model.verifiedCallerNumber = number
              path.append(.verified)
            }
          case .verified:
            CallVerifiedView { path.append(.contacts) }
          case .contacts:
            ConnectContactsView(onFinish: finish)
          }
        }
    }
  }

  /// Setup is done; the dialer takes over.
  private func finish() {
    dismiss()
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(400))
      model.isDialerPresented = true
    }
  }
}
