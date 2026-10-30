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
    guard !isRunning else { return }
    guard isCurrent() else {
      failed("資料が変更されたか、現在のワークスペースで開けません。資料を開き直して、もう一度お試しください。")
      return
    }
    let id = UUID()
    requestID = id
    progress = .preparing
    task = Task {
      do {
        let url = try await DocumentPDF.write(document) { value in
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
