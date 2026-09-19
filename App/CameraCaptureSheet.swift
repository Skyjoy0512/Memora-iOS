import SwiftUI

/// The camera surface offered from the composer's attachment menu. The UI is
/// in place; capturing is not wired up yet.
struct CameraCaptureSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var shutter = 0

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 24) {
        HStack {
          Spacer()

          Button("カメラを閉じる", systemImage: "xmark") {
            dismiss()
          }
          .labelStyle(.iconOnly)
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(.white.opacity(0.12), in: Circle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)

        Spacer(minLength: 12)

        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(.white.opacity(0.06))
          .overlay {
            VStack(spacing: 10) {
              Image(systemName: "camera.viewfinder")
                .font(.system(size: 44, weight: .light))
              Text("カメラで撮影")
                .font(.headline)
              Text("プレビューは準備中です")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white.opacity(0.85))
          }
          .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .stroke(.white.opacity(0.15), lineWidth: 1)
          }
          .aspectRatio(3.0 / 4.0, contentMode: .fit)
          .padding(.horizontal, 24)

        Spacer(minLength: 12)

        Button {
          shutter += 1
          dismiss()
        } label: {
          Circle()
            .stroke(.white, lineWidth: 4)
            .frame(width: 72, height: 72)
            .overlay {
              Circle()
                .fill(.white)
                .frame(width: 58, height: 58)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("撮影")
        .sensoryFeedback(.impact(weight: .heavy), trigger: shutter)
        .padding(.bottom, 36)
      }
    }
  }
}
