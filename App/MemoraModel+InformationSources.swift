import Foundation

extension MemoraModel {
  /// Picker, Open In and saved imports share the same size-triggered fallback.
  /// Only genuine large PDFs enter the bounded native partitioner.
  func importInformationSources(_ url: URL, context: LocalImportContext,
                                presentsErrorsLocally: Bool = false) async throws -> [UUID]? {
    guard context.isCurrent(in: self) else { return nil }
    do {
      guard let id = try await importProjectFile(url, projectID: context.projectID, importContext: context,
        presentsErrorsLocally: presentsErrorsLocally, waitsForPreparation: false) else { return nil }
      return [id]
    } catch ProjectSourceFiles.Failure.tooLarge {
      guard try PDFSourcePartitioning.requiresPartition(url) else { throw ProjectSourceFiles.Failure.tooLarge }
      let partition = try await PDFSourcePartitioning.prepare(url)
      defer { partition.cleanup() }
      guard context.isCurrent(in: self) else { return nil }
      return try await importPDFParts(partition, context: context)
    }
  }
}
