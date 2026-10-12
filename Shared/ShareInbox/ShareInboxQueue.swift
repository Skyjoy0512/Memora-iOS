import Foundation

actor ShareInboxQueue {
  var root: URL
  static let maximumItems = 10
  static let maximumFileBytes = 50 * 1024 * 1024
  static let maximumRequestBytes = 100 * 1024 * 1024
  static let maximumQueueBytes = 500 * 1024 * 1024
  init(root: URL) { self.root = root }

  enum Failure: LocalizedError {
    case invalid, tooLarge, full
    var errorDescription: String? {
      switch self {
      case .invalid: "共有内容を読み込めませんでした。元のアプリからもう一度共有してください。"
      case .tooLarge: "1ファイル50MB、1回の共有100MB・10項目まで保存できます。"
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
    guard (values.fileSize ?? Int.max) <= maximumFileBytes else { throw Failure.tooLarge }
    let extensionHint = url.pathExtension.isEmpty ? preferredExtension ?? "" : url.pathExtension
    let suffix = String(extensionHint.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(12))
    let name = UUID().uuidString + (suffix.isEmpty ? "" : "." + suffix)
    let output = folder.appendingPathComponent(name)
    FileManager.default.createFile(atPath: output.path, contents: nil)
    let reader = try FileHandle(forReadingFrom: url)
    let writer = try FileHandle(forWritingTo: output)
    defer { try? reader.close(); try? writer.close() }
    var count = 0
    do {
      while let data = try reader.read(upToCount: 64 * 1024), !data.isEmpty {
        try Task.checkCancellation()
        count += data.count
        guard count <= maximumFileBytes else { throw Failure.tooLarge }
        try writer.write(contentsOf: data)
      }
      try writer.synchronize()
    } catch { try? FileManager.default.removeItem(at: output); throw error }
    return name
  }

  func publish(_ request: ShareInboxRequest) throws {
    let folder = root.appendingPathComponent(".partial-" + request.id.uuidString, isDirectory: true)
    try validate(request, folder: folder)
    let pending = try requests()
    guard pending.count < 20, try occupiedBytes() <= Self.maximumQueueBytes else { throw Failure.full }
    let data = try JSONEncoder().encode(request)
    guard data.count <= 2 * 1024 * 1024 else { throw Failure.tooLarge }
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
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.invalid }
    guard (values.fileSize ?? Int.max) <= Self.maximumFileBytes else { throw Failure.tooLarge }
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
    var total = 0
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
      case .file:
        let url = try safeFile(item.value, folder: folder)
        let size = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard size.isRegularFile == true, size.isSymbolicLink != true else { throw Failure.invalid }
        guard let bytes = size.fileSize, bytes <= Self.maximumFileBytes else { throw Failure.tooLarge }
        total += bytes
      }
    }
    guard total <= Self.maximumRequestBytes else { throw Failure.tooLarge }
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

  private func occupiedBytes() throws -> Int {
    guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]) else { return 0 }
    var total = 0
    for case let url as URL in files {
      let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
      guard values.isSymbolicLink != true else { throw Failure.invalid }
      total += values.fileSize ?? 0
      if total > Self.maximumQueueBytes { throw Failure.full }
    }
    return total
  }
}
