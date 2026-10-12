import SwiftUI

/// The always-available way to ask about whatever is on screen. It sits on the
/// floating control layer with the bottom bar, so it uses the same glass.
struct QuickAIComposer: View {
  @Environment(MemoraModel.self) private var model
  var scope: AIQueryScope
  /// Lets the bottom bar step aside while someone is typing.
  @Binding var isComposing: Bool
  /// Keeps the keyboard up after sending on the Ask AI tab. The field is never
  /// focused on its own, so switching tabs does not raise the keyboard.
  var keepsFocusAfterSubmit = false
  /// Focuses the field when it appears, for the full-screen Ask AI opening.
  var autofocus = false
  @State private var attachment: AIAttachment?
  /// The question handed to the focused screen. It is built when the sheet
  /// opens, so clearing the composer afterwards cannot empty what is being asked.
  @State private var pendingQuestion: AIQuestionRequest?
  @State private var pendingProjectQuestion: AIQuestionRequest?
  @State private var confirmsCloudRequest = false
  @State private var isPreparingAttachment = false
  @State private var projectError: String?

  var body: some View {
    // The draft lives in the model, so rebuilding this view or leaving the tab
    // does not lose what was being typed.
    @Bindable var model = model

    return AIComposerBar(
      text: $model.composerDraft,
      attachment: $attachment,
      placeholder: placeholder,
      isBusy: isPreparingAttachment || model.activeProjectChatID.map { model.projectChatBusyIDs.contains($0) } == true,
      keepsFocusAfterSubmit: keepsFocusAfterSubmit,
      autofocus: autofocus,
      onSubmit: submit(attachment:),
      expansionChanged: { expanded in
        isComposing = expanded
      }
    )
    .sheet(item: $pendingQuestion) { request in
      AIQuestionView(request: request)
    }
    .confirmationDialog("登録済みのAIへ送信しますか？", isPresented: $confirmsCloudRequest, titleVisibility: .visible) {
      Button("送信") {
        if let request = pendingProjectQuestion { startProjectRequest(request, allowsPaidRequest: true) }
        pendingProjectQuestion = nil
      }
      Button("キャンセル", role: .cancel) { pendingProjectQuestion = nil }
    } message: {
      Text("質問、送信が許可された資料、最近の会話を送ります。利用するプロバイダーの料金が発生する場合があります。")
    }
    .alert("送信できませんでした", isPresented: Binding(get: { projectError != nil }, set: { if !$0 { projectError = nil } })) {
      Button("OK", role: .cancel) { projectError = nil }
    } message: { Text(projectError ?? "") }
  }

  /// Naming the scope saves a trip to the range picker in the common case.
  private var placeholder: String {
    switch scope {
    case .file(let meetingID):
      model.meeting(id: meetingID).map { "「\($0.title)」に質問" } ?? "この会議に質問"
    case .space(let spaceID):
      model.space(id: spaceID).map { "「\($0.name)」に質問" } ?? "このプロジェクトに質問"
    case .global:
      // On Ask AI itself the hint follows the mode the switch is set to.
      if model.selectedTab == .askAI {
        "Memoraに話しかける"
      } else {
        "Memoraに質問"
      }
    }
  }

  private var canSend: Bool {
    !model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil
  }

  /// True when the send is accepted; the composer clears the field only then,
  /// so a question typed while an answer is on its way is not lost.
  private func submit(attachment submitted: AIAttachment?) -> Bool {
    guard canSend else { return false }

    // A whole-library question belongs in the Ask AI chat, from whichever list
    // tab it was typed on; it switches there so the answer and the follow-ups
    // stay in one thread. A record or project question opens the answer sheet.
    if scope == .global {
      let trimmed = model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
      model.selectedTab = .askAI
      return model.sendAIChat(
        trimmed.isEmpty ? "この添付を確認して" : trimmed,
        attachment: submitted
      )
    }

    // The request is built from what is on screen now; the composer is only
    // cleared by the bar once this returns true.
    let trimmed = model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    let request = AIQuestionRequest(question: trimmed.isEmpty ? "このソースを確認して" : trimmed, scope: scope, attachment: submitted)
    if case .space = scope {
      if AIEngineService.effectiveEngine(model.askAIConfiguration.engine) == .cloud {
        pendingProjectQuestion = request
        confirmsCloudRequest = true
      } else {
        startProjectRequest(request, allowsPaidRequest: false)
      }
      return false
    }
    pendingQuestion = request
    return true
  }
  private func startProjectRequest(_ request: AIQuestionRequest, allowsPaidRequest: Bool) {
    guard case .space(let projectID) = request.scope, !isPreparingAttachment else { return }
    let existingChat = model.activeProjectChatID.flatMap { model.projectChat(id: $0) }
    guard existingChat?.projectID == projectID || existingChat == nil else { return }
    isPreparingAttachment = true
    Task { @MainActor in
      defer { isPreparingAttachment = false }
      do {
        if let attached = request.attachment {
          guard let id = try await model.importProjectFile(attached.url, projectID: projectID) else {
            projectError = "添付を保存できませんでした。質問は入力欄に残っています。"
            return
          }
          if model.source(id: id) != nil {
            await model.prepareProjectSource(id)
            guard let saved = model.source(id: id), saved.canProvideText else {
              projectError = "添付は保存しましたが、参照できる本文がまだありません。ソース詳細で解析状態を確認してください。"
              return
            }
            if AIEngineService.effectiveEngine(model.askAIConfiguration.engine) == .cloud,
               !RecordAccessPolicy.allows(saved.privacy, purpose: .cloudAI) {
              model.libraryPath.append(.projectSource(id))
              projectError = "添付は保存しました。外部AIへ送る場合は、ソース詳細のプライバシー設定で送信を許可してください。"
              return
            }
          } else {
            projectError = "音声は録音として保存しました。文字起こしと送信許可を確認してから質問してください。"
            return
          }
        }
        guard model.space(id: projectID) != nil else { return }
        guard let id = existingChat?.id ?? model.createProjectChat(projectID: projectID),
              model.sendProjectChat(id, question: request.question, allowsPaidRequest: allowsPaidRequest) else {
          projectError = "回答中でないことと質問が選択モデルの文字数上限以内であることを確認してください。"
          return
        }
        model.openProjectChat(id)
        if model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines) == request.question {
          model.composerDraft = ""
        }
        if attachment?.id == request.attachment?.id { attachment = nil }
      } catch {
        projectError = "添付を保存できませんでした。元ファイルと質問は残っています。"
      }
    }
  }
}
