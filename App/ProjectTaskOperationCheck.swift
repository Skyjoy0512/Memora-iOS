#if DEBUG
import Foundation
import Observation

@MainActor @Observable
final class ProjectTaskOperationCheck {
  var projectID: UUID?
  var result = ""
  private var recordIDs: Set<UUID> = []
  private var taskIDs: Set<UUID> = []

  func start(in model: MemoraModel) {
    guard model.currentTeamID == nil, !model.isRestoring, !model.isStoreProtected,
          cleanup(in: model), let project = model.addSpace(name: "QA 関連タスク検証") else { return }
    projectID = project
    let record = Meeting(id: UUID(), title: "QA プロジェクトの資料と次回会議で確認する長い記録名の表示検証",
      createdAt: .now, duration: 0, source: .importFile, status: .ready,
      summary: "表示・操作検証用の架空の記録です。音声・モデル・外部APIは使用していません。",
      keyPoints: [], decisions: [], openQuestions: [], transcript: [], spaceID: project)
    var outside = record
    outside.id = UUID(); outside.title = "QA 対象外の記録"; outside.spaceID = nil
    recordIDs = [record.id, outside.id]
    let additions = [
      MemoraTask(id: UUID(), title: "QA 自分の見積書を確認", meetingID: record.id, isCompleted: false, ownedByMe: true),
      MemoraTask(id: UUID(), title: "QA 別担当の翻訳レビューと長いタスク名の折り返しを確認する", meetingID: record.id,
        assignee: "田中（検証用）", isCompleted: false, ownedByMe: false),
      MemoraTask(id: UUID(), title: "QA 担当未定の課題", meetingID: record.id, isCompleted: false),
      MemoraTask(id: UUID(), title: "QA 完了済みの課題", meetingID: record.id, isCompleted: true),
      MemoraTask(id: UUID(), title: "QA 混入してはいけない別記録の課題", meetingID: outside.id, isCompleted: false),
      MemoraTask(id: UUID(), title: "QA 混入してはいけない全体タスク", isCompleted: false, ownedByMe: true)
    ]
    taskIDs = Set(additions.map(\.id))
    let records = [record, outside] + model.meetings
    let tasks = additions + model.tasks
    guard model.persistBatch(meetings: records, { [
      (key: MemoraModel.StorageKey.tasks, data: try RecordStore.encoded(tasks))
    ] }) else { result = "検証データを保存できませんでした。"; return }
    model.meetings = records; model.tasks = tasks
    if case .data(let data) = RecordStore.load(MemoraModel.StorageKey.tasks),
       let stored = try? JSONDecoder().decode([MemoraTask].self, from: data),
       additions.allSatisfy({ value in stored.first { $0.id == value.id } == value }),
       model.projectTasks(projectID: project).count == 3,
       model.projectTasks(projectID: project, includeCompleted: true).count == 4 {
      result = "SQLite保存・再読込一致。対象は未完了3件/完了を含め4件。対象外2件は表示しません。"
    } else { result = "保存と対象範囲を確認できませんでした。" }
  }

  func verify(in model: MemoraModel) {
    guard let projectID, case .data(let data) = RecordStore.load(MemoraModel.StorageKey.tasks),
          let stored = try? JSONDecoder().decode([MemoraTask].self, from: data),
          model.tasks.filter({ taskIDs.contains($0.id) }) == stored.filter({ taskIDs.contains($0.id) }) else {
      result = "編集後のSQLite再読込を確認できませんでした。"; return
    }
    result = "編集後もSQLite再読込一致。現在の対象: 未完了\(model.projectTasks(projectID: projectID).count)件、完了を含め\(model.projectTasks(projectID: projectID, includeCompleted: true).count)件。"
  }

  @discardableResult
  func cleanup(in model: MemoraModel) -> Bool {
    guard model.currentTeamID == nil, !model.isRestoring, !model.isStoreProtected else { return false }
    guard let projectID else { return true }
    // A check never removes content somebody added to its project or records.
    guard !model.tasks.contains(where: { !taskIDs.contains($0.id) && $0.meetingID.map(recordIDs.contains) == true }),
          !model.meetings.contains(where: { $0.spaceID == projectID && !recordIDs.contains($0.id) }),
          !model.projectSources.contains(where: { $0.projectID == projectID }),
          !model.projectChats.contains(where: { $0.projectID == projectID }),
          !model.documents.contains(where: { $0.spaceID == projectID }) else {
      result = "追加された内容があるため削除していません。検証プロジェクトの内容を確認してください。"; return false
    }
    let tasks = model.tasks.filter { !taskIDs.contains($0.id) }
    let records = model.meetings.filter { !recordIDs.contains($0.id) }
    let spaces = model.spaces.filter { $0.id != projectID }
    guard model.persistBatch(meetings: records, { [
      (key: MemoraModel.StorageKey.tasks, data: try RecordStore.encoded(tasks)),
      (key: MemoraModel.StorageKey.spaces, data: try RecordStore.encoded(spaces))
    ] }) else { result = "検証データを削除できませんでした。"; return false }
    model.tasks = tasks; model.meetings = records; model.spaces = spaces
    taskIDs.forEach { TaskReminderScheduler.cancel(taskID: $0) }
    if model.recentProjectIDs.contains(projectID) {
      model.recentProjectIDs.removeAll { $0 == projectID }
      UserDefaults.standard.set(model.recentProjectIDs.map(\.uuidString), forKey: "memora.projects.recentIDs")
    }
    self.projectID = nil; taskIDs = []; recordIDs = []
    result = "今回の検証データだけを削除しました。"
    return true
  }
}
#endif
