import SwiftUI

struct ToolsPrimaryAction: View {
  var title: String
  var action: () -> Void

  var body: some View {
    let button = Button(action: action) {
      Text(title)
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
        .contentShape(Capsule())
    }
    .tint(MemoraPalette.action)
    .foregroundStyle(MemoraPalette.actionLabel)
    .buttonBorderShape(.capsule)
    .controlSize(.large)

    if #available(iOS 26.0, *) {
      button.buttonStyle(.glassProminent)
    } else {
      button.buttonStyle(.borderedProminent)
    }
  }
}
