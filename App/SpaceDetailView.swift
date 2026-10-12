import SwiftUI

struct SpaceDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var spaceID: UUID
  @AppStorage("memora.projects.layout") private var layout = FileListLayout.card
  @AppStorage("memora.projects.sort") private var sort = FileListSort.newest
  @State private var isAskingAI = false
  @State private var isRenaming = false
  @State private var isDeleting = false
  @State private var isAddingFiles = false
  @State private var editingTask: MemoraTask?
  @State private var movingMeeting: Meeting?
  @State private var showsAllTasks = false
  @State private var showsAllRecords = false
  @State private var showsAllDocuments = false

  var body: some View {
    if let space = model.space(id: spaceID) {
      let records = ProjectFiling.records(in: spaceID, from: model.meetings)
      let tasks = openTasks(in: records)
      let documents = model.documents.filter { $0.spaceID == spaceID }.sorted { $0.updatedAt > $1.updatedAt }
      let orderedRecords = (showsAllRecords ? sort : FileListSort.newest).ordered(records)
      let visibleRecords = showsAllRecords ? orderedRecords : Array(orderedRecords.prefix(3))
      let visibleTasks = showsAllTasks ? tasks : Array(tasks.prefix(3))
      let visibleDocuments = showsAllDocuments ? documents : Array(documents.prefix(3))
      let isEmpty = records.isEmpty && tasks.isEmpty && documents.isEmpty

      List {
        Section {
          Text("記録 \(records.count)件 · 未完了タスク \(tasks.count)件")
            .font(.footnote).foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
        }
        if isEmpty {
          Section {
            VStack(alignment: .leading, spacing: 12) {
              Text("最初の記録を追加").font(.headline)
              Text("右下の＋から録音・音声取り込みを始められます。保存済みの記録も移動できます。")
                .font(.subheadline).foregroundStyle(.secondary)
              Button("ライブラリから記録を移動") { isAddingFiles = true }
                .frame(minHeight: 44)
                .tint(MemoraPalette.textPrimary)
                .disabled(model.isRestoring)
            }
            .padding(.vertical, 24)
            .listRowSeparator(.hidden)
          }
        } else {
          Section {
            if tasks.isEmpty {
              Text("未完了タスクはありません").font(.footnote).foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
            } else {
              ForEach(visibleTasks) { task in
                TaskRow(task: task, showsSource: true) { editingTask = task }
                  .buttonStyle(.plain)
              }
            }
          } header: {
            sectionHeading("次にやること", count: tasks.count, expanded: $showsAllTasks)
          }
          Section {
            if records.isEmpty {
              Text("まだ記録はありません").font(.footnote).foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
            } else {
              ForEach(visibleRecords) { meeting in fileRow(meeting) }
            }
          } header: {
            sectionHeading(showsAllRecords ? "記録 · \(sort.label)" : "最近の記録", count: records.count, expanded: $showsAllRecords)
          }
          if !documents.isEmpty {
            Section {
              ForEach(visibleDocuments) { document in
                NavigationLink(value: LibraryRoute.document(document.id)) {
                  ProjectDocumentRow(document: document)
                }
                .buttonStyle(.plain)
              }
            } header: {
              sectionHeading("関連資料", count: documents.count, expanded: $showsAllDocuments)
            } footer: {
              Text("AI質問は録音・タスクが対象です。資料本文の検索には対応していません。")
                .font(.footnote)
            }
          }
        }
      }
      .listStyle(.plain)
      .listSectionSpacing(24)
      .listRowInsets(EdgeInsets(top: 8, leading: ProjectLayout.horizontalInset, bottom: 8, trailing: ProjectLayout.horizontalInset))
      .scrollContentBackground(.hidden)
      .background(MemoraPalette.background)
      .onAppear { model.noteProjectUsed(space.id) }
      .onChange(of: spaceID) { _, _ in
        showsAllTasks = false
        showsAllRecords = false
        showsAllDocuments = false
      }
      .hideBottomBarOnScroll(model.selectedTab.rawValue)
      .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
      .navigationTitle(space.name)
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            if !isEmpty {
              Button("既存記録を移動", icon: .folder) { isAddingFiles = true }
            }
            Button("未決事項を質問", icon: .sparkles) { isAskingAI = true }
            Button("チームで共有", icon: .personBadgePlus) {
              Task { await model.shareSpaceWithTeam(space.id) }
            }
            if !records.isEmpty {
              if records.count <= 3, !showsAllRecords {
                Button("すべての記録を表示") { showsAllRecords = true }
              }
              Picker("全件の表示", selection: $layout) {
                ForEach(FileListLayout.allCases) { Text($0.label).tag($0) }
              }
              Picker("全件の並べ替え", selection: $sort) {
                ForEach(FileListSort.allCases) { Text($0.label).tag($0) }
              }
            }
            Divider()
            Button("名前を変更", icon: .pencil) { isRenaming = true }
            Button("削除", icon: .trash, role: .destructive) { isDeleting = true }
          } label: {
            ToolbarActionLabel("その他", icon: .ellipsis)
          }
        }
      }
      .sheet(isPresented: $isAddingFiles) { ProjectFilePickerSheet(spaceID: spaceID) }
      .interactionFeedback(.tap, trigger: isAddingFiles) { _, presented in presented }
      .sheet(item: $movingMeeting) { meeting in
        BulkSpacePickerSheet(meetingIDs: [meeting.id], onMove: {})
      }
      .sheet(isPresented: $isAskingAI) {
        AIQuestionView(scope: .space(space.id), askingQuestion: "このプロジェクトでまだ決まっていないことは？")
      }
      .sheet(isPresented: $isRenaming) { RenameSpaceSheet(space: space) }
      .sheet(item: $editingTask) { task in TaskEditView(task: task) }
      .confirmationDialog("このプロジェクトを削除しますか？", isPresented: $isDeleting, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          if model.deleteSpace(space.id) { dismiss() }
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("ファイルと資料は削除されず、未分類に移動します。")
      }
    } else {
      ContentUnavailableView("プロジェクトが見つかりません", icon: .folderBadgeQuestionmark)
    }
  }

  private func sectionHeading(_ title: String, count: Int, expanded: Binding<Bool>) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      if count > 3 || expanded.wrappedValue {
        Button(expanded.wrappedValue ? "折りたたむ" : "すべて見る（\(count)）") {
          expanded.wrappedValue.toggle()
        }
        .font(.subheadline)
        .frame(minHeight: 44)
        .tint(MemoraPalette.textPrimary)
        .accessibilityLabel("\(title)を\(expanded.wrappedValue ? "折りたたむ" : "すべて見る")")
        .accessibilityValue("\(count)件、\(expanded.wrappedValue ? "全件表示" : "一部表示")")
      }
    }
    .textCase(nil)
  }

  private func fileRow(_ meeting: Meeting) -> some View {
    NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
      if showsAllRecords, layout == .card {
        MeetingCard(meeting: meeting)
      } else {
        ProjectRecordRow(meeting: meeting)
      }
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("プロジェクトへ移動", icon: .folder) { movingMeeting = meeting }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button("移動", icon: .folder) { movingMeeting = meeting }
        .tint(.blue)
    }
  }

  private func openTasks(in spaceMeetings: [Meeting]) -> [MemoraTask] {
    let meetingIDs = Set(spaceMeetings.map(\.id))
    return model.tasks.filter { task in
      task.meetingID.map(meetingIDs.contains) == true && !task.isCompleted
    }
  }
}
