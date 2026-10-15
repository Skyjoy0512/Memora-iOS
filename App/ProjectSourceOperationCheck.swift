#if DEBUG
import Foundation
import Observation

@MainActor @Observable
final class ProjectSourceOperationCheck {
  var result = ""
  var isRunning = false
  var sourceIDs: Set<UUID> = []
  private var projectID: UUID?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var shouldCleanUp = false

  func start(in model: MemoraModel) {
    guard !isRunning, model.currentTeamID == nil, !model.isRestoring, !model.isStoreProtected,
          cleanup(in: model), let project = model.addSpace(name: "QA Office ソース検証") else { return }
    projectID = project
    shouldCleanUp = false
    isRunning = true
    result = "検証ファイルを取り込み中…"
    task = Task {
      defer {
        isRunning = false; task = nil
        if shouldCleanUp { _ = cleanup(in: model) }
      }
      let root = FileManager.default.temporaryDirectory.appendingPathComponent("OfficeCheck-\(UUID())")
      defer { try? FileManager.default.removeItem(at: root) }
      do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = try OfficeSourceFixtures.write(in: root)
        for file in files {
          try Task.checkCancellation()
          guard model.currentTeamID == nil,
                let id = try await model.importProjectFile(file, projectID: project) else { throw CheckFailure.failed }
          sourceIDs.insert(id)
          try Task.checkCancellation()
          guard let source = model.source(id: id), source.canProvideText, source.textCoverage == .partial,
                !source.privacy.allowsCloudAI, let reference = source.extractedTextReference else { throw CheckFailure.failed }
          let blocks = try await ProjectSourceTextReader.readAsync(reference)
          guard blocks.contains(where: { $0.text.contains("MEMORA OFFICE FIXTURE") }) else { throw CheckFailure.failed }
          let attachment = await AIAttachmentText.prepare(AIAttachment(id: UUID(), name: file.lastPathComponent, url: file))
          guard attachment.text?.contains("MEMORA OFFICE FIXTURE") == true, attachment.failure == nil else { throw CheckFailure.failed }
        }
        guard case .data(let data) = RecordStore.load(MemoraModel.StorageKey.projectSources),
              let stored = try? JSONDecoder().decode([ProjectSource].self, from: data),
              sourceIDs.allSatisfy({ id in stored.first { $0.id == id } == model.source(id: id) }) else { throw CheckFailure.failed }
        result = "3形式の取込・本文再読込・添付解析が成功。SQLite再読込一致: \(sourceIDs.count)件。外部送信はオフです。"
      } catch {
        result = error is CancellationError ? "検証を停止しました。" : "検証に失敗しました。\(error.localizedDescription)"
      }
    }
  }

  @discardableResult
  func cleanup(in model: MemoraModel) -> Bool {
    if isRunning { shouldCleanUp = true; task?.cancel(); return false }
    guard model.currentTeamID == nil else { result = "個人ワークスペースへ戻って検証データを削除してください。"; return false }
    for id in sourceIDs { model.deleteProjectSource(id) }
    guard sourceIDs.allSatisfy({ model.source(id: $0) == nil }) else { result = "検証ソースを削除できませんでした。"; return false }
    sourceIDs = []
    if let projectID, model.space(id: projectID) != nil {
      // Never detach or delete anything somebody added to this project during a check.
      guard !model.projectSources.contains(where: { $0.projectID == projectID }),
            !model.meetings.contains(where: { $0.spaceID == projectID }),
            !model.documents.contains(where: { $0.spaceID == projectID }),
            !model.projectChats.contains(where: { $0.projectID == projectID }),
            model.deleteSpace(projectID) else { result = "検証プロジェクトに別の内容があるか、削除できませんでした。"; return false }
    }
    projectID = nil
    result = "検証データを削除しました。"
    return true
  }

  private enum CheckFailure: LocalizedError {
    case failed
    var errorDescription: String? { "取込・本文・権限・保存の結果を確認できませんでした。" }
  }
}
#endif
