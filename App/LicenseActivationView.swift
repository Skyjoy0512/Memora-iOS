import SwiftUI

/// Activates a company license from the code the company was issued. The code
/// is checked on the device against Memora's signing key; nothing is sent.
struct LicenseActivationView: View {
  @Environment(MemoraModel.self) private var model
  @State private var code = ""
  @State private var errorMessage: String?
  @State private var isConfirmingRemoval = false
  @FocusState private var isFieldFocused: Bool

  var body: some View {
    MemoraForm {
      if let license = model.activeLicense {
        Section {
          LabeledContent("会社", value: license.company)
          LabeledContent("プラン", value: license.plan.label)
          LabeledContent("席数", value: "\(license.seats)")
          LabeledContent("有効期限", value: license.expiresAt.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(Locale(identifier: "ja_JP"))))
        } header: {
          Text("有効なライセンス")
        } footer: {
          Text("このライセンスのプランが、この端末のプラン設定より優先されます。")
        }

        Section {
          Button("ライセンスを外す", role: .destructive) {
            isConfirmingRemoval = true
          }
        }
      } else {
        Section {
          TextField("MEMORA-…", text: $code, axis: .vertical)
            .lineLimit(2...6)
            .font(.callout.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isFieldFocused)
            .accessibilityLabel("ライセンスコード")

          Button("有効にする", action: activate)
            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
          Text("ライセンスコード")
        } footer: {
          Text("会社の管理者から受け取ったコードを貼り付けます。コードはこの端末で確認し、外部には送りません。")
        }
      }
      if let errorMessage {
        Section {
          Label(errorMessage, icon: .exclamationmarkTriangle)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("法人ライセンス")
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog("ライセンスを外しますか？", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
      Button("外す", role: .destructive, action: remove)
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("記録は消えません。チーム機能とライセンスのプランが使えなくなります。")
    }
  }

  private func activate() {
    do {
      try model.activateLicense(code: code)
      code = ""
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func remove() {
    do {
      try model.removeLicense()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
