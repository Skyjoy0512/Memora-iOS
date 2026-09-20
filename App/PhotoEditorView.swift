import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Crops and adjusts a photo before it is stored: drag to reposition, pinch to
/// zoom, choose a shape, rotate, and tune brightness and contrast.
struct PhotoEditorView: View {
  @Environment(\.dismiss) private var dismiss
  var source: Data
  var onComplete: (Data) -> Void

  @State private var original: UIImage?
  /// The rotated, adjusted, downscaled image shown while editing.
  @State private var preview: UIImage?
  @State private var aspect = PhotoAspect.original
  @State private var quarterTurns = 0
  @State private var brightness: Double = 0
  @State private var contrast: Double = 1
  @State private var scale: CGFloat = 1
  @State private var offset = CGSize.zero
  @State private var lastMagnification: CGFloat = 1
  @State private var lastDrag = CGSize.zero
  @State private var viewport = CGSize.zero
  @State private var isExporting = false
  @State private var previewTask: Task<Void, Never>?

  private let ciContext = CIContext()

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        cropArea
        controls
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("写真を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { finish() }
            .disabled(preview == nil || isExporting)
        }
      }
      .onAppear(perform: load)
      .onChange(of: brightness) { _, _ in schedulePreview() }
      .onChange(of: contrast) { _, _ in schedulePreview() }
      .onChange(of: aspect) { _, _ in clamp() }
    }
  }

  private var cropArea: some View {
    GeometryReader { proxy in
      let size = viewportSize(availableWidth: proxy.size.width)

      ZStack {
        Color(uiColor: .secondarySystemBackground)

        if let preview {
          Image(uiImage: preview)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .offset(offset)
        }
      }
      .frame(width: size.width, height: size.height)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .gesture(magnificationGesture(size))
      .simultaneousGesture(dragGesture(size))
      .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
      .onAppear {
        viewport = size
        clamp()
      }
      .onChange(of: size) { _, newValue in
        viewport = newValue
        clamp()
      }
    }
    .frame(height: 320)
  }

  private var controls: some View {
    VStack(spacing: 14) {
      Picker("比率", selection: $aspect) {
        ForEach(PhotoAspect.allCases) { option in
          Text(option.label).tag(option)
        }
      }
      .pickerStyle(.segmented)

      HStack(spacing: 12) {
        Button("回転", systemImage: "rotate.right") {
          quarterTurns += 1
          scale = 1
          offset = .zero
          updatePreview()
          clamp()
        }
        .buttonStyle(.bordered)

        Button("リセット", systemImage: "arrow.counterclockwise") {
          brightness = 0
          contrast = 1
          quarterTurns = 0
          scale = 1
          offset = .zero
          updatePreview()
          clamp()
        }
        .buttonStyle(.bordered)
        .disabled(quarterTurns == 0 && brightness == 0 && contrast == 1)
      }

      slider(title: "明るさ", symbol: "sun.max", value: $brightness, range: -0.4...0.4)
      slider(title: "コントラスト", symbol: "circle.lefthalf.filled", value: $contrast, range: 0.6...1.6)
    }
  }

  private func slider(
    title: String,
    symbol: String,
    value: Binding<Double>,
    range: ClosedRange<Double>
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(title, systemImage: symbol)
        .font(.footnote)
        .foregroundStyle(.secondary)

      Slider(value: value, in: range)
        .accessibilityLabel(title)
    }
  }

  // MARK: - Geometry

  private func viewportSize(availableWidth: CGFloat) -> CGSize {
    let ratio = aspect.ratio(for: preview?.size)
    let maxHeight: CGFloat = 320
    var width = max(1, availableWidth)
    var height = width / ratio
    if height > maxHeight {
      height = maxHeight
      width = height * ratio
    }
    return CGSize(width: width, height: height)
  }

  private func magnificationGesture(_ size: CGSize) -> some Gesture {
    MagnifyGesture()
      .onChanged { value in
        let delta = value.magnification / (lastMagnification == 0 ? 1 : lastMagnification)
        lastMagnification = value.magnification
        scale = min(max(1, scale * delta), 6)
        clamp(size)
      }
      .onEnded { _ in
        lastMagnification = 1
        clamp(size)
      }
  }

  private func dragGesture(_ size: CGSize) -> some Gesture {
    DragGesture()
      .onChanged { value in
        let delta = CGSize(
          width: value.translation.width - lastDrag.width,
          height: value.translation.height - lastDrag.height
        )
        lastDrag = value.translation
        offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
        clamp(size)
      }
      .onEnded { _ in
        lastDrag = .zero
        clamp(size)
      }
  }

  /// Keeps the crop inside the image, so no empty edges can be exported.
  private func clamp(_ size: CGSize? = nil) {
    let area = size ?? viewport
    guard let preview, area.width > 0, area.height > 0 else {
      offset = .zero
      return
    }

    scale = min(max(1, scale), 6)

    let fillScale = max(area.width / preview.size.width, area.height / preview.size.height)
    let displayed = CGSize(
      width: preview.size.width * fillScale * scale,
      height: preview.size.height * fillScale * scale
    )
    let maxX = max(0, (displayed.width - area.width) / 2)
    let maxY = max(0, (displayed.height - area.height) / 2)
    offset = CGSize(
      width: min(max(offset.width, -maxX), maxX),
      height: min(max(offset.height, -maxY), maxY)
    )
  }

  // MARK: - Rendering

  private func load() {
    guard let image = UIImage(data: source)?.normalizedOrientation() else { return }
    original = image
    updatePreview()
  }

  private func schedulePreview() {
    previewTask?.cancel()
    previewTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(40))
      guard !Task.isCancelled else { return }
      updatePreview()
    }
  }

  private func updatePreview() {
    guard let original else { return }
    let rotated = original.rotated(quarterTurns: quarterTurns)
    let small = rotated.downscaled(maxSide: 900)
    preview = small.applyingAdjustments(
      brightness: brightness,
      contrast: contrast,
      context: ciContext
    ) ?? small
    clamp()
  }

  private func finish() {
    guard let original, let preview else { return }
    isExporting = true

    let area = viewport
    let turns = quarterTurns
    let bright = brightness
    let cont = contrast
    let zoom = scale
    let pan = offset
    let previewSize = preview.size

    let rotated = original.rotated(quarterTurns: turns)
    let adjusted = rotated.applyingAdjustments(brightness: bright, contrast: cont, context: ciContext) ?? rotated

    let ratio = adjusted.size.width / max(1, previewSize.width)
    let rect = cropRect(area: area, imageSize: previewSize, zoom: zoom, pan: pan)
    let scaled = CGRect(
      x: rect.origin.x * ratio,
      y: rect.origin.y * ratio,
      width: rect.width * ratio,
      height: rect.height * ratio
    )

    guard let cropped = adjusted.cropped(to: scaled),
          let data = cropped.jpegData(compressionQuality: 0.9) else {
      isExporting = false
      return
    }

    onComplete(data)
    dismiss()
  }

  private func cropRect(area: CGSize, imageSize: CGSize, zoom: CGFloat, pan: CGSize) -> CGRect {
    let fillScale = max(area.width / imageSize.width, area.height / imageSize.height)
    let unit = fillScale * zoom
    let visibleWidth = area.width / unit
    let visibleHeight = area.height / unit
    let centerX = imageSize.width / 2 - pan.width / unit
    let centerY = imageSize.height / 2 - pan.height / unit

    var rect = CGRect(
      x: centerX - visibleWidth / 2,
      y: centerY - visibleHeight / 2,
      width: visibleWidth,
      height: visibleHeight
    )
    rect.origin.x = min(max(0, rect.origin.x), max(0, imageSize.width - visibleWidth))
    rect.origin.y = min(max(0, rect.origin.y), max(0, imageSize.height - visibleHeight))
    return rect
  }
}

/// Carries a picked photo into the editor as a sheet item.
struct PhotoEditRequest: Identifiable {
  let id = UUID()
  var data: Data
}

enum PhotoAspect: String, CaseIterable, Identifiable {
  case original
  case square
  case wide

  var id: Self { self }

  var label: String {
    switch self {
    case .original: "オリジナル"
    case .square: "正方形"
    case .wide: "16:9"
    }
  }

  func ratio(for imageSize: CGSize?) -> CGFloat {
    switch self {
    case .original:
      guard let imageSize, imageSize.height > 0 else { return 1 }
      return imageSize.width / imageSize.height
    case .square:
      return 1
    case .wide:
      return 16.0 / 9.0
    }
  }
}

private extension UIImage {
  /// Draws the image upright with a 1:1 scale, so points and pixels agree.
  func normalizedOrientation() -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      draw(in: CGRect(origin: .zero, size: size))
    }
  }

  func rotated(quarterTurns: Int) -> UIImage {
    let turns = ((quarterTurns % 4) + 4) % 4
    guard turns != 0 else { return self }

    let radians = CGFloat(turns) * .pi / 2
    let newSize = turns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: newSize, format: format).image { context in
      let cg = context.cgContext
      cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
      cg.rotate(by: radians)
      draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
    }
  }

  func applyingAdjustments(brightness: Double, contrast: Double, context: CIContext) -> UIImage? {
    guard brightness != 0 || contrast != 1 else { return self }
    guard let ciImage = CIImage(image: self) else { return nil }

    let filter = CIFilter.colorControls()
    filter.inputImage = ciImage
    filter.brightness = Float(brightness)
    filter.contrast = Float(contrast)
    filter.saturation = 1

    guard let output = filter.outputImage,
          let cgImage = context.createCGImage(output, from: output.extent) else {
      return nil
    }
    return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
  }

  func downscaled(maxSide: CGFloat) -> UIImage {
    let longest = max(size.width, size.height)
    guard longest > maxSide, longest > 0 else { return self }

    let ratio = maxSide / longest
    let target = CGSize(width: size.width * ratio, height: size.height * ratio)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      draw(in: CGRect(origin: .zero, size: target))
    }
  }

  func cropped(to rect: CGRect) -> UIImage? {
    guard let cgImage else { return nil }
    let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
    let clamped = rect.intersection(bounds).integral
    guard !clamped.isNull, clamped.width > 0, clamped.height > 0,
          let cropped = cgImage.cropping(to: clamped) else {
      return nil
    }
    return UIImage(cgImage: cropped, scale: 1, orientation: .up)
  }
}
