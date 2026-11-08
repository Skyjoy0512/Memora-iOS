#if DEBUG
import Foundation
import Observation

@MainActor @Observable
final class AudioSourceEvidenceCheck {
  var result = ""
  var isRunning = false
  private var projectID: UUID?
  private var sourceID: UUID?
  private var textReference: String?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var shouldCleanUp = false

  func start(in model: MemoraModel) {
    guard !isRunning, model.currentTeamID == nil, !model.isRestoring, !model.isStoreProtected,
          cleanup(in: model), let project = model.addSpace(name: "QA 音声・字幕検証") else { return }
    projectID = project
    shouldCleanUp = false
    isRunning = true
    result = "検証中…"
    task = Task {
      defer {
        isRunning = false; task = nil
        if shouldCleanUp { _ = cleanup(in: model) }
      }
      do {
        let data = try JSONEncoder().encode([ProjectSourceText(text: "予算は1200万円です。", time: 12.5)])
        let name = try await ProjectSourceFiles.shared.write(data, extension: "json")
        textReference = name
        var source = ProjectSource(projectID: project, kind: .video, title: "音声引用検証")
        source.extractedTextReference = name
        source.processingStatus = .ready
        source.textCoverage = .partial
        guard model.storeProjectSource(source) else { throw Failure.failed }
        sourceID = source.id
        guard let context = try? await SourceContentSearch.context(source: source, question: "予算", budget: 4_000),
              context.used.contains(where: { $0.target == .source(source.id) && $0.time == 12.5 }),
              await model.matchingSourceIDs(query: "予算", projectID: project, scoped: true).contains(source.id) else {
          throw Failure.failed
        }
        var grounded = AIChatMessage(role: .assistant, text: "根拠【資料:\(source.id.uuidString)】")
        grounded.sourceCitations = context.used
        let allowed = model.answerCitationTargets(for: grounded)
        guard allowed.contains(.projectFile(source.id)),
              AnswerSourceCitation.linked(grounded.text, allowed: allowed)
                .contains(AnswerSourceCitation.url(for: .projectFile(source.id)).absoluteString) else { throw Failure.failed }
        guard case .data(let stored) = RecordStore.load(MemoraModel.StorageKey.projectSources),
              let decoded = try? JSONDecoder().decode([ProjectSource].self, from: stored),
              decoded.first(where: { $0.id == source.id }) == model.source(id: source.id) else { throw Failure.failed }
        result = "時刻12.5秒の引用・検索・引用リンク・SQLite一致を確認。外部送信はオフです。"
      } catch {
        result = error is CancellationError ? "検証を停止しました。" : "検証に失敗しました。\(error.localizedDescription)"
      }
    }
  }

  @discardableResult
  func cleanup(in model: MemoraModel) -> Bool {
    if isRunning { shouldCleanUp = true; task?.cancel(); return false }
    guard model.currentTeamID == nil else {
      result = "個人ワークスペースへ戻って検証データを削除してください。"
      return false
    }
    if let sourceID { _ = model.deleteProjectSource(sourceID) }
    guard sourceID == nil || model.source(id: sourceID!) == nil else {
      result = "検証ソースを削除できませんでした。"
      return false
    }
    if let projectID, model.space(id: projectID) != nil {
      guard !model.projectSources.contains(where: { $0.projectID == projectID }),
            model.deleteSpace(projectID) else {
        result = "検証プロジェクトに別の内容があるか、削除できませんでした。"
        return false
      }
    }
    if let textReference {
      let reference = textReference
      Task { await ProjectSourceFiles.shared.remove([reference]) }
    }
    projectID = nil; sourceID = nil; textReference = nil
    result = "検証データを削除しました。"
    return true
  }

  private enum Failure: LocalizedError {
    case failed
    var errorDescription: String? { "引用位置・検索・リンク・保存の結果を確認できませんでした。" }
  }
}
#endif
