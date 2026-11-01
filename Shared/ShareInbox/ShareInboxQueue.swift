import Foundation

actor ShareInboxQueue {
  var root: URL
  static let maximumItems = 10
  static let maximumFileBytes = 50 * 1024 * 1024
  static let maximumRequestBytes = 100 * 1024 * 1024
  static let maximumPDFBytes = 500 * 1024 * 1024
  static let maximumCombinedRequestBytes = 500 * 1024 * 1024
  static let maximumQueueBytes = 1_024 * 1024 * 1024
  init(root: URL) { self.root = root }

  enum Failure: LocalizedError {
    case invalid, tooLarge, full
    var errorDescription: String? {
      switch self {
      case .invalid: "共有内容を読み込めませんでした。元のアプリからもう一度共有してください。"
      case .tooLarge: "PDFは1ファイル500MB、その他は1ファイル50MB・合計100MBまで。1回の共有は全体で500MB・10項目まで保存できます。"
      case .full: "未取り込みの共有が多すぎます。Memoraを開いて取り込んでから再度共有してください。"
      }
    }
  }

  func projects() throws -> [ShareInboxProject] {
    let url = root.appendingPathComponent("projects.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let data = try boundedData(url, maximum: 256 * 1024)
    return Array(try JSONDecoder().decode([ShareInboxProject].self, from: data).prefix(1_000))
  }

  func updateProjects(_ projects: [ShareInboxProject]) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(Array(projects.prefix(1_000)))
    guard data.count <= 256 * 1024 else { throw Failure.tooLarge }
    try data.write(to: root.appendingPathComponent("projects.json"), options: .atomic)
  }

  func draft(_ id: UUID) throws -> URL {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let folder = root.appendingPathComponent(".partial-" + id.uuidString, isDirectory: true)
    guard !FileManager.default.fileExists(atPath: folder.path) else { throw Failure.invalid }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    return folder
  }

  // The provider owns its temporary URL only during its callback. Copy here,
  // before returning from that callback, rather than crossing an actor await.
  static func stageFile(_ url: URL, in folder: URL, preferredExtension: String? = nil) throws -> String {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.invalid }
    guard let size = values.fileSize, size >= 0, size <= maximumPDFBytes else { throw Failure.tooLarge }
    let reader = try FileHandle(forReadingFrom: url)
    defer { try? reader.close() }
    let header = try reader.read(upToCount: 5) ?? Data()
    let isPDF = header == Data("%PDF-".utf8)
    let maximum = isPDF ? maximumPDFBytes : maximumFileBytes
    guard size <= maximum else { throw Failure.tooLarge }
    let budget = try stagedBytes(in: folder)
    let occupied = try occupiedBytes(in: folder.deletingLastPathComponent())
    guard budget.count < maximumItems,
          size <= maximumCombinedRequestBytes - budget.total,
          isPDF || size <= maximumRequestBytes - budget.ordinary else { throw Failure.tooLarge }
    guard size <= maximumQueueBytes - occupied else { throw Failure.full }
    let extensionHint = url.pathExtension.isEmpty ? preferredExtension ?? "" : url.pathExtension
    let suffix = isPDF ? "pdf" : String(extensionHint.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(12))
    let name = UUID().uuidString + (suffix.isEmpty ? "" : "." + suffix)
    let output = folder.appendingPathComponent(name)
    guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw Failure.invalid }
    let writer = try FileHandle(forWritingTo: output)
    defer { try? writer.close() }
    var count = 0
    do {
      try reader.seek(toOffset: 0)
      while let data = try reader.read(upToCount: 64 * 1024), !data.isEmpty {
        try Task.checkCancellation()
        count += data.count
        guard count <= maximum,
              count <= maximumCombinedRequestBytes - budget.total,
              isPDF || count <= maximumRequestBytes - budget.ordinary else { throw Failure.tooLarge }
        guard count <= maximumQueueBytes - occupied else { throw Failure.full }
        try writer.write(contentsOf: data)
      }
      guard count == size else { throw Failure.invalid }
      if isPDF { guard try pdfHeader(output) else { throw Failure.invalid } }
      try writer.synchronize()
    } catch { try? FileManager.default.removeItem(at: output); throw error }
    return name
  }

  func publish(_ request: ShareInboxRequest) throws {
    let folder = root.appendingPathComponent(".partial-" + request.id.uuidString, isDirectory: true)
    try validate(request, folder: folder)
    let pending = try requests()
    let data = try JSONEncoder().encode(request)
    guard data.count <= 2 * 1024 * 1024 else { throw Failure.tooLarge }
    guard pending.count < 20, try Self.occupiedBytes(in: root) <= Self.maximumQueueBytes - data.count else { throw Failure.full }
    try data.write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    try FileManager.default.moveItem(at: folder, to: root.appendingPathComponent(request.id.uuidString, isDirectory: true))
  }

  func requests() throws -> [ShareInboxRequest] {
    let result = try inspect()
    guard result.invalidIDs.isEmpty else { throw Failure.invalid }
    return result.requests
  }

  func inspect() throws -> (requests: [ShareInboxRequest], invalidIDs: [UUID]) {
    guard FileManager.default.fileExists(atPath: root.path) else { return ([], []) }
    var values: [ShareInboxRequest] = []
    var invalidIDs: [UUID] = []
    for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
      guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
      do {
        let data = try boundedData(folder.appendingPathComponent("manifest.json"), maximum: 2 * 1024 * 1024)
        let request = try JSONDecoder().decode(ShareInboxRequest.self, from: data)
        guard request.id == id else { throw Failure.invalid }
        try validate(request, folder: folder)
        values.append(request)
      } catch { invalidIDs.append(id) }
      guard values.count + invalidIDs.count <= 20 else { throw Failure.full }
    }
    return (values.sorted { $0.createdAt < $1.createdAt }, invalidIDs)
  }

  func file(_ name: String, requestID: UUID) throws -> URL {
    let folder = root.appendingPathComponent(requestID.uuidString, isDirectory: true)
    let url = try safeFile(name, folder: folder)
    _ = try Self.fileBytes(url)
    return url
  }

  func remove(_ id: UUID, draft: Bool = false) throws {
    let name = (draft ? ".partial-" : "") + id.uuidString
    let url = root.appendingPathComponent(name, isDirectory: true)
    guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path + "/") else { throw Failure.invalid }
    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
  }

  func clearAbandonedDrafts() throws {
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]) {
      guard folder.lastPathComponent.hasPrefix(".partial-"),
            let id = UUID(uuidString: String(folder.lastPathComponent.dropFirst(9))),
            let date = try folder.resourceValues(forKeys: [.creationDateKey]).creationDate,
            date < Date.now.addingTimeInterval(-86_400) else { continue }
      try remove(id, draft: true)
    }
  }

  private func validate(_ request: ShareInboxRequest, folder: URL) throws {
    guard !request.items.isEmpty, request.items.count <= Self.maximumItems,
          Set(request.items.map(\.id)).count == request.items.count else { throw Failure.invalid }
    var total = 0, ordinary = 0
    for item in request.items {
      guard item.title.count <= 200 else { throw Failure.invalid }
      switch item.kind {
      case .link:
        guard item.value.utf8.count <= 8_192, let url = URLComponents(string: item.value),
              url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { throw Failure.invalid }
      case .text:
        guard !item.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.value.utf8.count <= 512 * 1024 else { throw Failure.tooLarge }
        total += item.value.utf8.count
        ordinary += item.value.utf8.count
      case .file:
        let url = try safeFile(item.value, folder: folder)
        let file = try Self.fileBytes(url)
        total += file.bytes
        if !file.isPDF { ordinary += file.bytes }
      }
    }
    guard ordinary <= Self.maximumRequestBytes, total <= Self.maximumCombinedRequestBytes else { throw Failure.tooLarge }
  }

  private func safeFile(_ name: String, folder: URL) throws -> URL {
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw Failure.invalid }
    let url = folder.appendingPathComponent(name)
    let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
    guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
          folder.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(rootPath),
          url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(folder.resolvingSymlinksInPath().standardizedFileURL.path + "/") else { throw Failure.invalid }
    return url
  }

  private func boundedData(_ url: URL, maximum: Int) throws -> Data {
    guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path + "/") else { throw Failure.invalid }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= maximum else { throw Failure.invalid }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximum + 1) ?? Data()
    guard data.count <= maximum else { throw Failure.tooLarge }
    return data
  }

  private static func pdfHeader(_ url: URL) throws -> Bool {
    let reader = try FileHandle(forReadingFrom: url)
    defer { try? reader.close() }
    return try reader.read(upToCount: 5) == Data("%PDF-".utf8)
  }

  private static func fileBytes(_ url: URL) throws -> (bytes: Int, isPDF: Bool) {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.invalid }
    guard let bytes = values.fileSize, bytes >= 0, bytes <= maximumPDFBytes else { throw Failure.tooLarge }
    // Filename and provider type alone must never raise the ordinary file limit.
    let isPDF = try url.pathExtension.lowercased() == "pdf" && pdfHeader(url)
    guard bytes <= (isPDF ? maximumPDFBytes : maximumFileBytes) else { throw Failure.tooLarge }
    return (bytes, isPDF)
  }

  private static func stagedBytes(in folder: URL) throws -> (total: Int, ordinary: Int, count: Int) {
    let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.invalid }
    var total = 0, ordinary = 0, count = 0
    for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
      let file = try fileBytes(url)
      total += file.bytes
      if !file.isPDF { ordinary += file.bytes }
      count += 1
      guard total <= maximumCombinedRequestBytes, ordinary <= maximumRequestBytes, count <= maximumItems else { throw Failure.tooLarge }
    }
    return (total, ordinary, count)
  }

  private static func occupiedBytes(in root: URL) throws -> Int {
    guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey]) else { throw Failure.invalid }
    var total = 0
    for case let url as URL in files {
      let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
      guard values.isSymbolicLink != true else { throw Failure.invalid }
      if values.isRegularFile == true { total += values.fileSize ?? 0 }
      if total > Self.maximumQueueBytes { throw Failure.full }
    }
    return total
  }
}
