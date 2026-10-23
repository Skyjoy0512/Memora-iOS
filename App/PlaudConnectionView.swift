import SwiftUI

struct PlaudConnectionView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      RecorderAudioImportView(title: "PLAUD", isPlaud: true)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("完了", icon: .checkmark) { dismiss() }
        }
      }
    }
  }
}
