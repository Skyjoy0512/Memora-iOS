import SwiftUI
import UniformTypeIdentifiers

struct ComposerDraftRecoveryView: View {
  @Environment(MemoraModel.self) private var model
  @State private var archives: [ComposerDraftRecoveryArchive.Reference] = []
  @State private var statusMessage: String?
  @State private var errorMessage: String?
  @State private var archiveError: String?
  @State private var exportDocument: ComposerDraftArchiveDocument?
  @State private var isExporting = false

  var body: some View {
    MemoraForm {
      ComposerDraftRecoveryStatusSection(
        failure: model.composerDraftFailure,
        storeProtected: model.isStoreProtected,
        canRecover: model.currentTeamID == nil && !model.isRestoring && !model.isStoreProtected && !model.isAIChatResponding,
        statusMessage: statusMessage, errorMessage: errorMessage, recover: recover)
      if model.currentTeamID == nil {
        ComposerDraftRecoveryArchivesSection(archives: archives, errorMessage: archiveError,
          canExport: !model.isRestoring, export: export, reload: reload)
      } else {
        Section { Text("下書きの復旧・書き出しは、個人ワークスペースへ切り替えてから行ってください。") }
      }
    }
    .navigationTitle("Ask AIの下書き")
    .navigationBarTitleDisplayMode(.inline)
    .task { reload() }
    .onChange(of: model.composerDraftFailure) { _, _ in reload() }
    .onChange(of: model.aiWorkspaceGeneration) { _, _ in
      isExporting = false
      exportDocument = nil
      reload()
    }
    .fileExporter(isPresented: $isExporting, document: exportDocument,
      contentType: .json, defaultFilename: "Memora-draft-recovery") { result in
      exportDocument = nil
      if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
        errorMessage = "書き出せませんでした。退避した元データは端末に残っています。"
      }
    }
  }

  private func recover() {
    statusMessage = nil
    errorMessage = nil
    do {
      try model.recoverComposerDraft()
      statusMessage = "元データを退避しました。入力を再開できます。"
      reload()
    } catch {
      errorMessage = "下書きを復旧できませんでした。元データは変更していません。空き容量と保存先を確認して再試行してください。"
    }
  }

  private func reload() {
    archives = []
    archiveError = nil
    guard model.currentTeamID == nil else { return }
    do { archives = try ComposerDraftStore.recoveryArchives() }
    catch { archiveError = "退避した下書きの一覧を読み込めませんでした。元データは変更していません。" }
  }

  private func export(_ archive: ComposerDraftRecoveryArchive.Reference) {
    guard model.currentTeamID == nil, !model.isRestoring else { return }
    do {
      exportDocument = ComposerDraftArchiveDocument(data: try ComposerDraftStore.archiveData(archive))
      isExporting = true
    } catch { errorMessage = "元データを読み込めなかったため、書き出しを止めました。端末のデータは変更していません。" }
  }
}

private struct ComposerDraftRecoveryStatusSection: View {
  var failure: ComposerDraftStore.Failure?
  var storeProtected: Bool
  var canRecover: Bool
  var statusMessage: String?
  var errorMessage: String?
  var recover: () -> Void

  var body: some View {
    Section {
      if failure != nil {
        Text("前回の下書きを読み込めないため、Ask AIの入力を保護しています。")
        if storeProtected || failure == .unavailable {
          Text("保存先の読み取りにも問題があります。データを保護するため、この起動では復旧できません。アプリを再起動してから確認してください。")
            .foregroundStyle(.secondary)
        } else {
          Text("元データを端末に残し、読み取れた本文を引き継いで入力を再開します。会議や保存済みの会話は変更しません。")
            .foregroundStyle(.secondary)
          Button("元データを退避して入力を再開", action: recover)
            .disabled(!canRecover || failure != .unreadable)
            .accessibilityIdentifier("composer.recovery.restore")
        }
      } else {
        Text("下書きは利用できます。")
      }
      if let statusMessage { Text(statusMessage).foregroundStyle(.secondary) }
      if let errorMessage {
        Text(errorMessage).foregroundStyle(MemoraPalette.danger)
          .accessibilityIdentifier("composer.recovery.failure")
      }
    } header: { Text("入力欄の状態") }
  }
}

private struct ComposerDraftRecoveryArchivesSection: View {
  var archives: [ComposerDraftRecoveryArchive.Reference]
  var errorMessage: String?
  var canExport: Bool
  var export: (ComposerDraftRecoveryArchive.Reference) -> Void
  var reload: () -> Void

  var body: some View {
    Section {
      if let errorMessage {
        Text(errorMessage).foregroundStyle(.secondary)
        Button("一覧を読み直す", action: reload)
      } else if archives.isEmpty {
        Text("退避した下書きはありません。")
          .foregroundStyle(.secondary)
      }
      ForEach(archives) { archive in
        Button { export(archive) } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text("元データを書き出す")
            Text(archive.createdAt, format: .dateTime.year().month().day().hour().minute())
              .font(.footnote).foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .disabled(!canExport)
      }
    } header: { Text("退避した元データ") } footer: {
      Text("元の入力内容と添付の参照情報を、調査用のファイルとして書き出せます。添付ファイル本体は含みません。退避データはこの端末に保存し、Memoraのバックアップ書き出しには含めません。")
    }
  }
}
