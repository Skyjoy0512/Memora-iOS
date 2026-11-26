import SwiftUI

struct ProjectChatView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var threadID: UUID
  @State private var isRenaming = false
  @State private var isDeleting = false
  @State private var editingTask: MemoraTask?
  @State private var viewingPhoto: ProjectPhoto?
  @State private var sourceMissing = false

  var body: some View {
    if let thread = model.projectChat(id: threadID) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 24) {
            if let projectID = thread.projectID, let project = model.space(id: projectID) {
              Text(project.name).font(MemoraTypography.metadata).foregroundStyle(.secondary)
            } else {
              Text("プロジェクトの所属を解除した会話です。履歴の閲覧はできます。")
                .font(MemoraTypography.secondary).foregroundStyle(.secondary)
            }
            ForEach(thread.messages) { message in
              VStack(alignment: .leading, spacing: 12) {
                if message.role == .user {
                  AIUserMessageView(text: message.text) { model.composerDraft = message.text }
                } else {
                  AIResponseText(text: message.text)
                }
                if message.role == .assistant {
                  AIResponseActionBar(text: message.text, retry: {})
                  if !message.citations.isEmpty {
                    DisclosureGroup("出典") {
                      ForEach(message.citations) { citation in
                        Button { open(citation, projectID: thread.projectID) } label: {
                          Label(citationLabel(citation), icon: citation.photo == nil ? .docText : .photo)
                            .font(MemoraTypography.metadata).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .tint(MemoraPalette.textPrimary)
                      }
                    }
                  }
                  if let engine = message.engineLabel { Text(engine).font(.caption).foregroundStyle(.secondary) }
                }
              }.id(message.id)
            }
            ProjectChatStreamingReply(threadID: threadID)
            if let stage = model.projectChatStages[threadID] {
              ProjectChatWaitingStatus(threadID: threadID, stage: stage)
              Button("回答を停止", icon: .stopFill) { model.cancelProjectChat(threadID) }
                .frame(minHeight: 44).tint(MemoraPalette.textPrimary)
            } else if let failure = thread.lastFailure {
              Text(failure).font(MemoraTypography.secondary).foregroundStyle(.secondary)
              Text("再試行する場合は、下の入力欄から改めて送信してください。")
                .font(MemoraTypography.metadata).foregroundStyle(.secondary)
            } else if thread.pendingMessageID != nil {
              Text("前の回答は中断されています。自動で再送はしません。")
                .font(MemoraTypography.secondary).foregroundStyle(.secondary)
            }
            Color.clear.frame(height: 1).id(ConversationScrollFollowing.bottomID)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(ProjectLayout.horizontalInset)
        }
        .modifier(ConversationScrollFollowing(proxy: proxy, latestMessageID: thread.messages.last?.id,
          isBusy: model.projectChatBusyIDs.contains(threadID), bottomInset: model.bottomContentClearance))
      }
      .background(MemoraPalette.background)
      .navigationTitle(thread.title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if model.projectChatBusyIDs.contains(threadID) {
          ToolbarItem(placement: .primaryAction) {
            ToolbarIconButton("回答を停止", icon: .stopFill) { model.cancelProjectChat(threadID) }
          }
        }
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            if let projectID = thread.projectID, model.space(id: projectID) != nil {
              Button("新しいチャット", icon: .squareAndPencil) {
                if let id = model.createProjectChat(projectID: projectID) { model.openProjectChat(id) }
              }
              NavigationLink("チャット履歴", value: LibraryRoute.projectChats(projectID))
            }
            Button("名前を変更", icon: .pencil) { isRenaming = true }
            Button("チャットを削除", icon: .trash, role: .destructive) { isDeleting = true }
          } label: { ToolbarActionLabel("その他", icon: .ellipsis) }
        }
      }
      .sheet(isPresented: $isRenaming) { ProjectChatRenameSheet(thread: thread) }
      .sheet(item: $editingTask) { task in TaskEditView(task: task) }
      .sheet(item: $viewingPhoto) { ProjectPhotoViewer(photo: $0) }
      .alert("元のソースが見つかりません", isPresented: $sourceMissing) { Button("閉じる", role: .cancel) {} }
      .confirmationDialog("このチャットを削除しますか？", isPresented: $isDeleting, titleVisibility: .visible) {
        Button("削除", role: .destructive) { if model.deleteProjectChat(threadID) { dismiss() } }
      } message: { Text("会話だけを削除します。ソースやプロジェクトは削除しません。") }
      .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    } else { ContentUnavailableView("チャットが見つかりません", icon: .chatBubble) }
  }

  private func citationLabel(_ citation: ProjectCitation) -> String {
    let location = citation.photo.map { _ in "写真の文字" } ?? citation.page.map { "ページ\($0)" }
      ?? ProjectCitationLocation.playbackTime(citation.time).map { MemoraFormat.duration($0) }
    return [citation.title, citation.recordDateLabel, location].compactMap { $0 }.joined(separator: " · ")
  }

  private func open(_ citation: ProjectCitation, projectID: UUID?) {
    guard let projectID, model.projectCitationAllowed(citation, projectID: projectID, cloud: false) else {
      sourceMissing = true
      return
    }
    switch citation.target {
    case .source(let id):
      if let source = model.source(id: id) {
        if source.kind == .pdf, let page = citation.page, page > 0 {
          model.libraryPath.append(.projectPDF(id, page))
        } else { model.libraryPath.append(.projectSource(id)) }
      } else { sourceMissing = true }
    case .meeting(let id):
      if let record = model.meeting(id: id) {
        if let photo = citation.photo {
          viewingPhoto = ProjectPhoto(name: photo.name, date: record.createdAt,
            recordID: id, recordTitle: record.displayTitle)
        } else if let time = ProjectCitationLocation.playbackTime(citation.time) {
          model.libraryPath.append(.meetingCitation(id, time))
        } else { model.libraryPath.append(.transcript(id)) }
      } else { sourceMissing = true }
    case .document(let id):
      if model.document(id: id) != nil { model.libraryPath.append(.document(id)) } else { sourceMissing = true }
    case .task(let id):
      editingTask = model.tasks.first { $0.id == id }
      if editingTask == nil { sourceMissing = true }
    }
  }
}
