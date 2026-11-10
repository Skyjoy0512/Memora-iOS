import SwiftUI

struct ComposerDraftRecoveryPrompt: View {
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      Label("下書きを読み込めません。確認する", icon: .docText)
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.bordered)
    .accessibilityHint("元の下書きを保護しています。復旧の方法を開きます")
    .accessibilityIdentifier("composer.recovery.open")
    .sheet(isPresented: $isPresented) {
      NavigationStack {
        ComposerDraftRecoveryView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              ToolbarIconButton("閉じる", icon: .xmark) { isPresented = false }
            }
          }
      }
    }
  }
}
