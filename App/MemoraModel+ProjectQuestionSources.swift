import Foundation

extension MemoraModel {
  /// Pasted links use the saved-source pipeline, including its deduplication,
  /// safe fetcher and legal caption path. A title alone cannot ground a reply.
  func prepareProjectQuestionLinks(_ question: String, context: LocalImportContext,
    cloud: Bool, isCurrent: () -> Bool
  ) async throws {
    guard let projectID = context.projectID else { throw CancellationError() }
    for url in InlineURLDetector.urls(in: question) {
      guard context.isCurrent(in: self), isCurrent() else { throw CancellationError() }
      guard let id = try await addProjectLink(url.absoluteString, projectID: projectID) else {
        throw ProjectQuestionSourceFailure.unavailable("リンクを保存できませんでした。入力は残しています。")
      }
      await prepareProjectSource(id)
      guard context.isCurrent(in: self), isCurrent() else { throw CancellationError() }
      guard let saved = source(id: id), saved.projectID == projectID else { throw CancellationError() }
      guard saved.canProvideText else {
        throw ProjectQuestionSourceFailure.unavailable(saved.errorInformation ??
          "リンクは保存しましたが、参照できる本文がありません。元の資料を確認して再試行してください。")
      }
      if cloud, !RecordAccessPolicy.allows(saved.privacy, purpose: .cloudAI) {
        throw ProjectQuestionSourceFailure.cloudRestricted(id)
      }
    }
  }
}
