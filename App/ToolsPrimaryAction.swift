import SwiftUI

struct ToolsPrimaryAction: View {
  var title: String
  var action: () -> Void

  var body: some View {
    let button = Button(action: action) {
      Text(title)
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Capsule())
    }
    .tint(MemoraPalette.action)
    .foregroundStyle(MemoraPalette.actionLabel)
    .buttonBorderShape(.capsule)

    if #available(iOS 26.0, *) {
      button.buttonStyle(.glassProminent)
    } else {
      button.buttonStyle(.borderedProminent)
    }
  }
}
