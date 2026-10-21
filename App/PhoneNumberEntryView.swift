import SwiftUI

/// The person's own number, which calls will show as the caller.
struct PhoneNumberEntryView: View {
  var onSubmit: (String) -> Void
  @State private var number = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    let e164 = PhoneNumberFormat.e164(number)

    VStack(alignment: .leading, spacing: 16) {
      Text("電話番号を登録")
        .font(.largeTitle.bold())
      Text("相手の画面にはこの番号が表示されます。番号は安全に扱います。")
        .foregroundStyle(.secondary)

      HStack(spacing: 10) {
        Text("🇯🇵 +81")
          .foregroundStyle(.secondary)
          .accessibilityLabel("日本 +81")
        TextField("090-1234-5678", text: $number)
          .keyboardType(.phonePad)
          .textContentType(.telephoneNumber)
          .focused($isFocused)
      }
      .font(.title3)
      .padding(.horizontal, MemoraSpacing.xl)
      .frame(minHeight: 56)
      .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
      .padding(.top, MemoraSpacing.md)

      Text("確認のため、この番号に電話がかかってきます。")
        .font(.footnote)
        .foregroundStyle(.secondary)

      CallPrimaryButton(title: "電話番号を追加", isEnabled: e164 != nil) {
        if let e164 { onSubmit(e164) }
      }
      .padding(.top, MemoraSpacing.md)

      Spacer()
    }
    .padding(MemoraSpacing.xxl)
    .background(MemoraPalette.background)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { isFocused = true }
  }
}
