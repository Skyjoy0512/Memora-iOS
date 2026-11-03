import SwiftUI
import UIKit

struct CameraCaptureView: View {
  var onPhoto: (Data) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @State private var controller = CameraCaptureController()

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if controller.isReady { CameraCapturePreview(controller: controller).ignoresSafeArea() }
      VStack {
        HStack {
          Button { dismiss() } label: {
            Image(icon: .xmarkCircle, size: 28).frame(width: 44, height: 44).contentShape(Circle())
          }
          .accessibilityLabel("カメラを閉じる")
          Spacer()
        }
        Spacer()
        if controller.permissionDenied {
          Text("資料を撮影するには、カメラへのアクセスを許可してください。")
            .multilineTextAlignment(.center)
          Button("設定を開く") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          }.frame(minHeight: 44)
        } else if let failure = controller.failure {
          Text(failure).multilineTextAlignment(.center)
          if !controller.isReady {
            Button("再試行") { Task { await controller.start() } }.frame(minHeight: 44)
          }
        } else if !controller.isReady {
          ProgressView("カメラを準備しています").tint(.white)
        }
        Spacer()
        Button { controller.capture(onPhoto: onPhoto) } label: {
          Circle().fill(.white).frame(width: 62, height: 62)
            .padding(8).overlay { Circle().stroke(.white, lineWidth: 3) }
            .contentShape(Circle())
        }
        .disabled(!controller.isReady || controller.isCapturing)
        .opacity(controller.isReady && !controller.isCapturing ? 1 : 0.4)
        .accessibilityLabel("資料を撮影")
      }
      .padding(24)
      .foregroundStyle(.white)
    }
    .buttonStyle(.plain)
    .task { await controller.start() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { controller.stop() }
      else if phase == .active && !controller.isReady { Task { await controller.start() } }
    }
    .onDisappear { controller.stop() }
  }
}
