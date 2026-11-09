import SwiftUI

struct MemoraSymbol: View {
  var size: CGFloat = 22

  var body: some View {
    Image("memora-symbol")
      .renderingMode(.original)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .accessibilityLabel("Memora")
  }
}
