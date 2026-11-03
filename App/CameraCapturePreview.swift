import AVFoundation
import SwiftUI
import UIKit

struct CameraCapturePreview: UIViewRepresentable {
  var controller: CameraCaptureController

  func makeUIView(context: Context) -> PreviewSurface {
    let view = PreviewSurface()
    view.previewLayer.session = controller.driver.session
    view.previewLayer.videoGravity = .resizeAspectFill
    controller.attachPreview(view.previewLayer)
    return view
  }

  func updateUIView(_ uiView: PreviewSurface, context: Context) {}

  final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
  }
}
