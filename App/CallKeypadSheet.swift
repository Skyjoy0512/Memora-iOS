import SwiftUI

/// Digits sent into a call in progress, such as for a phone menu.
struct CallKeypadSheet: View {
  var onDigit: (String) -> Void
  @State private var typed = ""

  private static let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]

  var body: some View {
    VStack(spacing: 14) {
      Text(typed.isEmpty ? " " : typed)
        .font(.title.monospacedDigit())
        .padding(.top, MemoraSpacing.xl)
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 20), count: 3), spacing: 12) {
        ForEach(Self.digits, id: \.self) { digit in
          Button {
            typed.append(digit)
            onDigit(digit)
          } label: {
            Text(digit)
              .font(.title2.weight(.medium))
              .frame(width: 70, height: 70)
              .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
          }
          .buttonStyle(.plain)
        }
      }
    }
    .frame(maxWidth: .infinity)
  }
}
