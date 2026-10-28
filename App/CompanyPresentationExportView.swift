import SwiftUI

struct CompanyPresentationExportView: View {
  var model: MemoraModel
  var document: MemoraDocument
  @State private var pending: CompanyPresentationExportRequest?
  @State private var active: CompanyPresentationExportRequest?
  @State private var confirmsExport = false
  @State private var showsFailure = false
  @State private var failure: String?
  @State private var notice: LocalizedStringResource?

  var body: some View {
    let blocker = model.companyPresentationExportBlocker(for: document)
    let template = model.companyTemplates.first { $0.id == document.companyTemplateID && $0.workspaceID == model.currentTeamID }
    CompanyPresentationExportControls(isWorking: active != nil, blockedReason: blocker?.errorDescription,
      templateName: template?.name, templateVersion: template?.version, notice: notice, start: confirm, cancel: cancel)
      .modifier(CompanyPresentationExportConfirmation(isPresented: $confirmsExport, request: pending) { request in
        active = request; pending = nil; notice = nil
      })
      .task(id: active?.id) {
        guard let request = active else { return }
        do {
          _ = try await model.reexportCompanyPresentation(request)
          guard active?.id == request.id else { return }
          active = nil
          notice = "会社PPTXを書き出しました。以前のファイルは履歴から確認できます。"
        } catch {
          guard active?.id == request.id else { return }
          active = nil
          if error is CancellationError { notice = "書き出しを取り消しました。" }
          else { failure = error.localizedDescription; showsFailure = true }
        }
      }
      .onChange(of: document.id) { _, _ in reset() }
      .onChange(of: model.aiWorkspaceGeneration) { _, _ in reset() }
      .onDisappear { active = nil; pending = nil }
      .alert("PPTXを書き出せませんでした", isPresented: $showsFailure) {
        Button("閉じる", role: .cancel) {}
      } message: { Text(failure ?? "") }
  }

  private func confirm() {
    guard active == nil else { return }
    do { pending = try model.companyPresentationExportRequest(for: document); confirmsExport = true; notice = nil }
    catch { failure = error.localizedDescription; showsFailure = true }
  }

  private func cancel() {
    guard active != nil else { return }
    active = nil
    notice = "書き出しを取り消しました。以前のファイルは変更していません。"
  }

  private func reset() {
    active = nil; pending = nil; confirmsExport = false; showsFailure = false; failure = nil; notice = nil
  }
}
