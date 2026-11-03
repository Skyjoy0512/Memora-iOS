import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class CameraCaptureController {
  private(set) var isReady = false
  private(set) var isCapturing = false
  private(set) var permissionDenied = false
  private(set) var failure: String?
  @ObservationIgnored let driver = CapturePhotoSession()
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var captureID = UUID()
  @ObservationIgnored private var timeout: Task<Void, Never>?
  @ObservationIgnored private var rotation: AVCaptureDevice.RotationCoordinator?
  @ObservationIgnored private var observation: NSKeyValueObservation?
  @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?
  @ObservationIgnored private var previewID = UUID()

  func start() async {
    let run = UUID()
    generation = run
    isReady = false
    failure = nil
    permissionDenied = false
    let allowed: Bool
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: allowed = true
    case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
    default: allowed = false
    }
    guard !Task.isCancelled, generation == run else { return }
    guard allowed else { permissionDenied = true; return }
    let ready = await driver.start()
    guard !Task.isCancelled, generation == run else { return }
    isReady = ready
    if !ready { failure = "カメラを利用できませんでした。接続と権限を確認して再試行してください。" }
  }

  func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
    guard let device = driver.device else { return }
    previewLayer = layer
    let id = UUID()
    previewID = id
    let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
    self.rotation = rotation
    observation = rotation.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] rotation, _ in
      let angle = rotation.videoRotationAngleForHorizonLevelPreview
      Task { @MainActor [weak self] in
        guard let self, self.previewID == id else { return }
        if let connection = self.previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) {
          connection.videoRotationAngle = angle
        }
      }
    }
  }

  func capture(onPhoto: @escaping @MainActor (Data) -> Void) {
    guard isReady, !isCapturing else { return }
    isCapturing = true
    failure = nil
    let run = generation, capture = UUID()
    captureID = capture
    timeout?.cancel()
    timeout = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(15)) } catch { return }
      guard let self, self.generation == run, self.captureID == capture else { return }
      self.captureID = UUID()
      self.isCapturing = false
      self.isReady = false
      self.driver.stop()
      self.failure = "撮影を完了できませんでした。カメラを開き直して再試行してください。"
    }
    driver.capture(rotation: rotation?.videoRotationAngleForHorizonLevelCapture ?? 90) { [weak self] data in
      Task { @MainActor in
        guard let self, self.generation == run, self.captureID == capture else { return }
        self.timeout?.cancel()
        self.timeout = nil
        self.isCapturing = false
        guard let data, !data.isEmpty, data.count <= ProjectSourceFiles.maximumFileBytes else {
          self.isReady = false
          self.driver.stop()
          self.failure = "写真を取得できませんでした。もう一度撮影してください。"
          return
        }
        onPhoto(data)
      }
    }
  }

  func stop() {
    generation = UUID()
    captureID = UUID()
    timeout?.cancel()
    timeout = nil
    observation = nil
    rotation = nil
    previewLayer = nil
    previewID = UUID()
    isReady = false
    isCapturing = false
    driver.stop()
  }
}
