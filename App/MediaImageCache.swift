import UIKit

/// Decoded photos for lists, decoded at the size they are drawn and off the main
/// thread, keyed by file name and size. File names are unique per photo, so an
/// entry can never be stale; decoded byte cost and memory pressure bound it.
@MainActor
enum MediaImageCache {
  private static let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 80
    cache.totalCostLimit = 64 * 1024 * 1024
    return cache
  }()
  private struct Request {
    var id = UUID()
    var generation: Int
    var task: Task<UIImage?, Never>
  }
  private static var pending: [String: Request] = [:]
  private static var generation = 0
  private static let memoryObserver = NotificationCenter.default.addObserver(
    forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
  ) { _ in
    MainActor.assumeIsolated {
      clear()
      SummaryPreviewCache.clear()
    }
  }

  /// The photo for a list, decoded at `maxPixelSize`.
  static func image(named name: String, maxPixelSize: CGFloat, recordsPerformance: Bool = true) async -> UIImage? {
    let key = "\(name)@\(Int(maxPixelSize))"
    guard let url = thumbnailURL(for: name) else { return nil }
    return await decoded(key: key, url: url, maxPixelSize: maxPixelSize, measured: recordsPerformance)
  }

  static func sourceThumbnail(named name: String, maxPixelSize: CGFloat) async -> UIImage? {
    let key = "workspace.\(name)@\(Int(maxPixelSize))"
    guard let url = ProjectSourceFiles.resolve(name),
          let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          size <= 256 * 1024 else { return nil }
    return await decoded(key: key, url: url, maxPixelSize: maxPixelSize)
  }

  /// The full-size photo, for the one being looked at.
  static func photo(named name: String, maxPixelSize: CGFloat = 2_000) async -> UIImage? {
    let key = "full.\(name)@\(Int(maxPixelSize))"
    guard let url = MediaFiles.photoURL(name) else { return nil }
    return await decoded(key: key, url: url, maxPixelSize: maxPixelSize)
  }

  private static func decoded(key rawKey: String, url: URL, maxPixelSize: CGFloat, measured: Bool = false) async -> UIImage? {
    // A legacy photo name can start with "full." or "workspace.". Include the
    // resource itself so different files never share a cached or in-flight load.
    let resource = url.absoluteString
    let key = "\(resource.utf8.count):\(resource)\(rawKey)"
    _ = memoryObserver
    guard !Task.isCancelled else { return nil }
    // A removed file must not be resurrected by an already decoded cache entry.
    guard FileManager.default.fileExists(atPath: url.path) else {
      cache.removeObject(forKey: key as NSString)
      return nil
    }
    if let cached = cache.object(forKey: key as NSString) { return cached }
    let request: Request
    var startedAt: Date?
    if let existing = pending[key] {
      request = existing
    } else {
      if measured { startedAt = .now }
      let task = Task.detached(priority: .userInitiated) {
        guard !Task.isCancelled else { return nil as UIImage? }
        return ImageDownscale.downsampled(at: url, maxPixelSize: maxPixelSize)
      }
      request = Request(generation: generation, task: task)
      pending[key] = request
    }
    let image = await request.task.value
    // One timing per real decode, independent of how many rows await it.
    if let startedAt, !request.task.isCancelled {
      PerformanceLog.shared.record("画像のデコード", milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000)
    }
    if pending[key]?.id == request.id {
      pending.removeValue(forKey: key)
      if let image, request.generation == generation, !request.task.isCancelled,
         FileManager.default.fileExists(atPath: url.path) {
        cache.setObject(image, forKey: key as NSString, cost: decodedCost(image))
      }
    }
    guard !Task.isCancelled, !request.task.isCancelled,
          FileManager.default.fileExists(atPath: url.path) else { return nil }
    return image
  }

  private static func decodedCost(_ image: UIImage) -> Int {
    if let cgImage = image.cgImage { return cgImage.bytesPerRow * cgImage.height }
    return Int(image.size.width * image.size.height * image.scale * image.scale * 4)
  }

  static func clear() {
    cache.removeAllObjects()
    // Visible rows still need the decode they await. Memory pressure evicts
    // cached images without leaving those rows stuck on a cancelled placeholder.
    generation += 1
  }

  /// The small copy when it exists; otherwise the original, which is all there
  /// is for photos saved before thumbnails did.
  private static func thumbnailURL(for name: String) -> URL? {
    MediaFiles.photoURL(MediaFiles.thumbnailName(for: name)) ?? MediaFiles.photoURL(name)
  }
}
