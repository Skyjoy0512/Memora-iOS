import AVFoundation
import Foundation

/// Configuration and capture live on one queue. Only the preview layer uses
/// the session outside it, after configuration has acknowledged completion.
final class CapturePhotoSession: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
  let session = AVCaptureSession()
  private(set) var device: AVCaptureDevice?
  private let queue = DispatchQueue(label: "app.memora.camera", qos: .userInitiated)
  private let output = AVCapturePhotoOutput()
  private var configured = false
  private var completion: (@Sendable (Data?) -> Void)?
  private var pendingPhotoID: Int64?

  func start() async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        if !configured {
          session.beginConfiguration()
          do {
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
            if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
              ?? AVCaptureDevice.default(for: .video) else { throw CocoaError(.featureUnsupported) }
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else { throw CocoaError(.featureUnsupported) }
            session.addInput(input)
            guard session.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
            session.addOutput(output)
            output.maxPhotoQualityPrioritization = .balanced
            device = camera
            configured = true
          } catch {
            session.commitConfiguration()
            continuation.resume(returning: false)
            return
          }
          session.commitConfiguration()
        }
        if !session.isRunning { session.startRunning() }
        continuation.resume(returning: session.isRunning)
      }
    }
  }

  func capture(rotation: CGFloat, completion: @escaping @Sendable (Data?) -> Void) {
    queue.async { [self] in
      guard configured, session.isRunning, self.completion == nil,
            output.availablePhotoCodecTypes.contains(.jpeg) else { completion(nil); return }
      self.completion = completion
      if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(rotation) {
        connection.videoRotationAngle = rotation
      }
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      settings.photoQualityPrioritization = .balanced
      pendingPhotoID = settings.uniqueID
      output.capturePhoto(with: settings, delegate: self)
    }
  }

  func stop() {
    queue.async { [self] in
      completion = nil
      pendingPhotoID = nil
      if session.isRunning { session.stopRunning() }
    }
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
    let data = error == nil ? photo.fileDataRepresentation() : nil
    let photoID = photo.resolvedSettings.uniqueID
    queue.async { [self] in
      // A timed-out capture must never settle a later retry.
      guard pendingPhotoID == photoID else { return }
      let callback = completion
      completion = nil
      pendingPhotoID = nil
      callback?(data)
    }
  }
}
