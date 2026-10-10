import SwiftUI

struct JournalBackdropView: View {
  var backdrop: JournalBackdrop
  var immersive = false
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    GeometryReader { geometry in
      Image(backdrop.assetName)
        .resizable()
        .scaledToFill()
        .frame(width: geometry.size.width, height: geometry.size.height)
        .blur(radius: immersive ? 3 : 0)
        .clipped()
        .overlay(Color.black.opacity(contrast == .increased ? 0.65 : immersive ? 0.5 : 0.28))
        .overlay {
          LinearGradient(colors: [.black.opacity(0.1), .black.opacity(immersive ? 0.82 : 0.66)],
            startPoint: .top, endPoint: .bottom)
        }
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}
