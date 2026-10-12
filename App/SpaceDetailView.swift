import SwiftUI
import UniformTypeIdentifiers

struct SpaceDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var spaceID: UUID
  @AppStorage("memora.projects.layout") private var layout = FileListLayout.card
  @AppStorage("memora.projects.sort") private var sort = FileListSort.newest
  @State private var isAskingAI = false
  @State private var isRenaming = false
  @State private var isDeleting = false
  @State private var isImporting = false
  @State private var isAddingFiles = false
  @State private var editingTask: MemoraTask?
  @State private var movingMeeting: Meeting?

  var body: some View {
    if let space = model.space(id: spaceID) {
      let spaceMeetings = sort.ordered(ProjectFiling.records(in: spaceID, from: model.meetings))
      let spaceTasks = openTasks(in: spaceMeetings)

      List {
        Section {
          overview(space, meetingCount: spaceMeetings.count, taskCount: spaceTasks.count)
        }
        Section {
          Button {
            InteractionFeedback.shared.send(.tap)
            isAskingAI = true
          } label: {
            HStack(spacing: 12) {
              Image(icon: .sparkles)
              Text("このプロジェクトについて聞く")
                .font(.body.weight(.semibold))
              Spacer()
              Image(icon: .arrowUpRight)
                .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        Section {
          if spaceMeetings.isEmpty {
            ContentUnavailableView {
              Label("まだファイルがありません", icon: .folder)
            } description: {
              Text("録音・インポートするか、既存のファイルを移動してまとめましょう。")
            } actions: {
              Button("既存ファイルを移動", icon: .folder) { isAddingFiles = true }
            }
          } else {
            ForEach(spaceMeetings) { meeting in fileRow(meeting) }
          }
        } header: {
          HStack {
            Text("ファイル")
            Spacer()
            Text("\(spaceMeetings.count)件 · \(sort.label)")
          }
        }
        Section("進行中のタスク · \(spaceTasks.count)件") {
          if spaceTasks.isEmpty {
            Label("未完了のタスクはありません", icon: .checkmark)
              .foregroundStyle(.secondary)
          } else {
            ForEach(spaceTasks) { task in
              TaskRow(task: task, showsSource: true) { editingTask = task }
                .buttonStyle(.plain)
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .onAppear { model.noteProjectUsed(space.id) }
      .hideBottomBarOnScroll(model.selectedTab.rawValue)
      .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
      .navigationTitle(space.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarActionItem {
          ToolbarIconButton("チームで共有", icon: .personBadgePlus) {
            Task { await model.shareSpaceWithTeam(space.id) }
          }
          .labelStyle(.iconOnly)
        }
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            Button("既存ファイルを移動", icon: .folder) { isAddingFiles = true }
            Picker("表示", selection: $layout) {
              ForEach(FileListLayout.allCases) { Text($0.label).tag($0) }
            }
            Picker("並べ替え", selection: $sort) {
              ForEach(FileListSort.allCases) { Text($0.label).tag($0) }
            }
            Divider()
            Button("名前を変更", icon: .pencil) { isRenaming = true }
            Button("削除", icon: .trash, role: .destructive) { isDeleting = true }
          } label: {
            ToolbarActionLabel("その他", icon: .ellipsis)
          }
        }
      }
      .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
        switch result {
        case .success(let url):
          let destinationID = spaceID
          Task { await model.importAudio(from: url, spaceID: destinationID) }
        case .failure(let error):
          model.importErrorMessage = error.localizedDescription
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

  private func overview(_ space: MemoraSpace, meetingCount: Int, taskCount: Int) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 14) {
        Image(icon: space.icon)
          .font(.title2.weight(.semibold))
          .frame(width: 52, height: 52)
          .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 5) {
          Text(space.name).font(.title2.bold())
          Text("\(meetingCount)件のファイル · \(taskCount)件の未完了タスク")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) { captureActions }
        VStack(spacing: 12) { captureActions }
      }
      Text("ここで録音・インポートしたファイルは、このプロジェクトに保存されます。")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Button("既存ファイルを移動", icon: .folder) { isAddingFiles = true }
        .frame(minHeight: 44)
        .disabled(model.isRestoring)
    }
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private var captureActions: some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      if model.isRecording {
        model.isCapturePresented = true
      } else {
        let destinationID = spaceID
        Task { await model.startCapture(spaceID: destinationID) }
      }
    } label: {
      Label(model.isRecording ? "録音画面を開く" : "録音を開始", icon: .mic)
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.borderedProminent)
    .disabled(model.isPreparingCapture || model.isSavingCapture || model.isRestoring)
    Button {
      InteractionFeedback.shared.send(.tap)
      isImporting = true
    } label: {
      Label(model.isImporting ? "読み込み中…" : "インポート", icon: .squareAndArrowDown)
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.bordered)
    .disabled(model.isImporting || model.isRestoring)
  }

  private func fileRow(_ meeting: Meeting) -> some View {
    NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
      if layout == .card {
        MeetingCard(meeting: meeting)
      } else {
        MeetingRow(meeting: meeting, showsDisclosure: false)
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
