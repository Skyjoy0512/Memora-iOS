import Foundation

enum PDFSourcePartitioning {
  static func requiresPartition(_ url: URL) throws -> Bool {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard url.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true,
          let bytes = values.fileSize else { throw ProjectSourceFiles.Failure.invalidFile }
    guard bytes > ProjectSourceFiles.maximumFileBytes else { return false }
    let reader = try FileHandle(forReadingFrom: url)
    defer { try? reader.close() }
    guard try reader.read(upToCount: 5) == Data("%PDF-".utf8) else { return false }
    guard bytes <= PDFSourcePartition.maximumInputBytes else { throw PDFSourcePartitionFailure.inputTooLarge }
    return true
  }

  static func prepare(_ url: URL, maximumParts: Int = PDFSourcePartition.maximumParts) async throws -> PDFSourcePartition {
    let worker = Task.detached(priority: .utility) {
      try await SourceProcessingQueue.shared.perform {
        try PDFSourcePartition.prepare(url, maximumParts: maximumParts)
      }
    }
    let partition = try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: { worker.cancel() }
    if Task.isCancelled { partition.cleanup(); throw CancellationError() }
    return partition
  }
}
