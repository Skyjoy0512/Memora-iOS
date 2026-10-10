import SwiftUI

struct TeamTaskBoardView: View {
  @Environment(MemoraModel.self) private var model
  @State private var snapshot: TeamTaskBoardSnapshot?
  @State private var selectedAssignee: String?
  @State private var ownOnly = false
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var requestID = UUID()

  var body: some View {
    let tasks = snapshot?.tasks.filter {
      (!ownOnly || snapshot?.ownTaskIDs.contains($0.id) == true)
        && (selectedAssignee == nil || $0.assignee == selectedAssignee)
    } ?? []
    let assignees = Array(Set((snapshot?.tasks ?? []).compactMap(\.assignee))).sorted()

    VStack(spacing: 12) {
      if let snapshot {
        HStack {
          Toggle("自分のみ", isOn: $ownOnly).toggleStyle(.button)
          Picker("担当", selection: $selectedAssignee) {
            Text("全メンバー").tag(String?.none)
            ForEach(assignees, id: \.self) { name in Text(name).tag(String?.some(name)) }
          }
          .pickerStyle(.menu)
          Spacer()
          if isLoading { ProgressView() }
        }
        .padding(.horizontal, 18)
        ScrollView(.horizontal) {
          HStack(alignment: .top, spacing: 14) {
            ForEach(TaskBoardColumn.allCases) { column in
              let items = TaskHierarchy.ordered(tasks.filter(column.contains))
              ScrollView {
              VStack(alignment: .leading, spacing: 12) {
                Text(column.title).font(.headline)
                ForEach(items) { task in
                  VStack(alignment: .leading, spacing: 8) {
                    Text(task.title).font(.body)
                    if let owner = task.assignee { Text(owner).font(.caption).foregroundStyle(.secondary) }
                    Menu("状態を変更") {
                      ForEach(TaskBoardColumn.allCases) { destination in
                        Button(destination.title) { Task { await move(task, to: destination, snapshot: snapshot) } }
                          .disabled(destination.contains(task))
                      }
                    }
                    .font(.caption)
                    .disabled(isLoading)
                  }
                  .padding(14)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                if items.isEmpty { Text("課題なし").font(.subheadline).foregroundStyle(.secondary) }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              }
              .frame(width: 260, alignment: .leading)
            }
          }
          .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .refreshable { await reload() }
      } else if isLoading {
        ProgressView("チームの課題を同期しています")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView("チーム課題は未接続です", icon: .person2, description: Text(errorMessage ?? "サイドメニューでチームを選択してください。チームのクラウドが接続されるまで課題は同期できません。個人のタスクは共有しません。"))
      }
      if snapshot != nil, let errorMessage {
        Text(errorMessage).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 18)
      }
      Button("再読み込み") { Task { await reload() } }.disabled(isLoading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.bottom, model.bottomContentClearance)
    .task(id: model.currentWorkspace.id) { await reload() }
    .onDisappear { requestID = UUID() }
  }

  private func reload() async {
    let identifier = UUID()
    requestID = identifier
    snapshot = nil
    selectedAssignee = nil
    guard case .team(let team) = model.currentWorkspace, model.hasTeamPlan else {
      isLoading = false
      errorMessage = nil
      return
    }
    isLoading = true
    errorMessage = nil
    do {
      let result = try await model.loadTeamTaskBoard(teamID: team.id)
      guard requestID == identifier else { return }
      snapshot = result
    } catch {
      guard requestID == identifier else { return }
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  private func move(_ task: MemoraTask, to column: TaskBoardColumn, snapshot original: TeamTaskBoardSnapshot) async {
    guard !isLoading else { return }
    let identifier = requestID
    isLoading = true
    do {
      let result = try await model.moveTeamTask(task, to: column, snapshot: original)
      guard requestID == identifier else { return }
      snapshot = result
      errorMessage = nil
    } catch {
      guard requestID == identifier else { return }
      errorMessage = error.localizedDescription
      snapshot = nil
    }
    isLoading = false
  }
}
