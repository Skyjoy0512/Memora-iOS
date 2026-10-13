#if DEBUG
import UIKit

/// Uses a private temporary image, never a person's media, to check request
/// sharing and deletion while exercising the same ImageIO path as list rows.
@MainActor
enum PerformanceCacheChecks {
  static func run() async -> String? {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 120)).image { context in
      UIColor.gray.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 240, height: 120))
    }
    guard let data = image.jpegData(compressionQuality: 0.8),
          let name = MediaFiles.writePhoto(data, thumbnailMaxSide: 120) else { return "fixture image write" }
    defer { MediaFiles.deletePhoto(name) }
    let requests = (0..<8).map { _ in Task { await MediaImageCache.photo(named: name, maxPixelSize: 120) } }
    var decoded: [UIImage] = []
    for request in requests {
      guard let value = await request.value else { return "shared decode failed" }
      decoded.append(value)
    }
    guard let first = decoded.first, decoded.allSatisfy({ $0 === first }),
          first.cgImage?.width == 120 else { return "duplicate decode or changed dimensions" }
    NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    guard let reloaded = await MediaImageCache.photo(named: name, maxPixelSize: 120),
          reloaded !== first, reloaded.cgImage?.width == first.cgImage?.width else {
      return "memory warning did not release cached image or changed dimensions"
    }
    let visibleRequest = Task { await MediaImageCache.photo(named: name, maxPixelSize: 119) }
    await Task.yield()
    NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    if await visibleRequest.value == nil { return "memory warning cancelled a visible image request" }
    let legacyName = "full." + name
    guard let legacyURL = MediaFiles.photoURL(legacyName),
          let thumbnailURL = MediaFiles.photoURL(MediaFiles.thumbnailName(for: legacyName)) else { return "fixture path" }
    defer { MediaFiles.deletePhoto(legacyName) }
    do {
      try data.write(to: legacyURL, options: .atomic)
      try data.write(to: thumbnailURL, options: .atomic)
    } catch { return "legacy fixture write" }
    guard let full = await MediaImageCache.photo(named: name, maxPixelSize: 120),
          let other = await MediaImageCache.image(named: legacyName, maxPixelSize: 120, recordsPerformance: false),
          full !== other else { return "cache key mixed different files" }
    let cancelled = Task { await MediaImageCache.photo(named: name) }
    cancelled.cancel()
    if await cancelled.value != nil { return "cancelled request returned image" }
    MediaFiles.deletePhoto(name)
    if await MediaImageCache.photo(named: name, maxPixelSize: 120) != nil { return "deleted image remained cached" }
    let id = UUID()
    let a = SummaryPreviewCache.preview(for: id, summary: "a") { "preview:" + $0 }
    let b = SummaryPreviewCache.preview(for: id, summary: "b") { "preview:" + $0 }
    SummaryPreviewCache.clear()
    let restored = SummaryPreviewCache.preview(for: id, summary: "b") { "preview:" + $0 }
    if a != "preview:a" || b != "preview:b" || restored != b { return "stale summary preview" }
    return nil
  }
}
#endif
