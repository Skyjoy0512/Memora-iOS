import Foundation

/// A bounded disposable cache. Diagnostic loss never changes a business save.
actor AudioDiagnosticArchive {
  static let shared = AudioDiagnosticArchive(directory: defaultDirectory)
  static let maximumBytes = 2 * 1024 * 1024
  static let maximumReports = 12
  private var reports: [AudioDiagnosticReport] = []
  private var loaded = false
  private var pendingSave: Task<Void, Never>?
  private var pendingGeneration: UUID?
  private var directory: URL
  private var file: URL { directory.appendingPathComponent("metrics.json") }

  private static var defaultDirectory: URL {
    #if MEMORA_HOST_CHECKS
    guard let path = ProcessInfo.processInfo.environment["MEMORA_AUDIO_DIAGNOSTICS_DIRECTORY"], path.hasPrefix("/") else {
      preconditionFailure("Host audio diagnostics directory is required")
    }
    return URL(fileURLWithPath: path, isDirectory: true)
    #else
    return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Memora/AudioDiagnostics")
    #endif
  }

  init(directory: URL) { self.directory = directory }

  func update(_ report: AudioDiagnosticReport, generation: UUID) {
    guard generation == AudioProcessingDiagnostics.generation, report.isValid else { return }
    loadIfNeeded()
    if let index = reports.firstIndex(where: { $0.id == report.id }) {
      guard reports[index].revision < report.revision else { return }
      reports[index] = report
    } else {
      reports.append(report)
      if reports.count > Self.maximumReports { reports.removeFirst(reports.count - Self.maximumReports) }
    }
    if pendingGeneration != generation {
      pendingSave?.cancel()
      pendingSave = nil
    }
    if pendingSave == nil {
      pendingGeneration = generation
      pendingSave = Task {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        flush(generation: generation)
      }
    }
  }

  func snapshot() -> [AudioDiagnosticReport] {
    loadIfNeeded()
    return reports.reversed()
  }

  func export() -> String {
    loadIfNeeded()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(reports), data.count <= Self.maximumBytes else { return "[]" }
    return String(decoding: data, as: UTF8.self)
  }

  func clear() {
    pendingSave?.cancel()
    pendingSave = nil
    pendingGeneration = nil
    loaded = true
    reports = []
    try? FileManager.default.removeItem(at: file)
  }

  func flush(generation: UUID) {
    guard pendingGeneration == generation else { return }
    pendingSave = nil
    pendingGeneration = nil
    guard generation == AudioProcessingDiagnostics.generation,
          let data = try? JSONEncoder().encode(reports), data.count <= Self.maximumBytes else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else { return }
      try data.write(to: file, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    } catch { }
  }

  private func loadIfNeeded() {
    guard !loaded else { return }
    loaded = true
    guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
          values.isRegularFile == true, values.isSymbolicLink != true,
          let bytes = values.fileSize, bytes <= Self.maximumBytes,
          let modified = values.contentModificationDate, Date.now.timeIntervalSince(modified) < 7 * 24 * 3600,
          let handle = try? FileHandle(forReadingFrom: file) else { return }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: Self.maximumBytes + 1), data.count <= Self.maximumBytes,
          var decoded = try? JSONDecoder().decode([AudioDiagnosticReport].self, from: data),
          decoded.count <= Self.maximumReports, decoded.allSatisfy(\.isValid) else { return }
    // Relaunch never pretends that a trace interrupted by process death finished.
    for index in decoded.indices where decoded[index].outcome == .running {
      decoded[index].outcome = .interrupted
    }
    reports = decoded
  }
}
