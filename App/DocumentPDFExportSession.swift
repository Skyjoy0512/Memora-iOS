import Foundation
import Observation

@MainActor @Observable
final class DocumentPDFExportSession {
  private(set) var progress: DocumentPDFProgress?
  @ObservationIgnored private var task: Task<Void, Never>?
  private var requestID: UUID?
  var isRunning: Bool { requestID != nil }

  func start(document: MemoraDocument, isCurrent: @escaping @MainActor () -> Bool,
             completed: @escaping @MainActor (URL) -> Void, failed: @escaping @MainActor (String) -> Void) {
    start(isCurrent: isCurrent, operation: { progress in
      try await DocumentPDF.write(document, onProgress: progress)
    }, completed: completed, failed: failed)
  }

  func start(isCurrent: @escaping @MainActor () -> Bool,
             operation: @escaping @MainActor (@escaping @MainActor @Sendable (DocumentPDFProgress) -> Void) async throws -> URL,
             completed: @escaping @MainActor (URL) -> Void, failed: @escaping @MainActor (String) -> Void) {
    guard !isRunning else { return }
    guard isCurrent() else {
      failed("内容が変更されたか、現在のワークスペースで開けません。開き直して、もう一度お試しください。")
      return
    }
    let id = UUID()
    requestID = id
    progress = .preparing
    task = Task {
      do {
        let url = try await operation { value in
          guard self.requestID == id else { return }
          if !isCurrent() { self.cancel(); return }
          if case .writing(let previous, let previousTotal) = self.progress {
            guard case .writing(let completed, let total) = value,
                  completed >= previous, total == previousTotal else { return }
          }
          self.progress = value
        }
        guard requestID == id, !Task.isCancelled, isCurrent() else {
          ArtifactExportFile.removeTemporary([url])
          if requestID == id { finish() }
          return
        }
        finish()
        completed(url)
      } catch {
        guard requestID == id else { return }
        let wasCancelled = Task.isCancelled || error is CancellationError || !isCurrent()
        finish()
        if !wasCancelled { failed(error.localizedDescription) }
      }
    }
  }

  func cancel() {
    task?.cancel()
    finish()
  }

  private func finish() {
    requestID = nil
    progress = nil
    task = nil
  }
}
