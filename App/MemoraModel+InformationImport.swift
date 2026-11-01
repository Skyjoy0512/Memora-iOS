import Foundation

extension MemoraModel {
  @discardableResult
  func importInformationFile(_ url: URL, context: LocalImportContext?) async -> UUID? {
    guard let context, context.isCurrent(in: self), !isImporting else { return nil }
    isImporting = true
    importErrorMessage = nil
    defer { isImporting = false }
    do {
      guard let id = try await importProjectFile(url, projectID: context.projectID, importContext: context,
        waitsForPreparation: false) else {
        importErrorMessage = persistenceFailureMessage ?? "資料を保存できませんでした。もう一度追加してください。"
        return nil
      }
      guard context.isCurrent(in: self) else { return nil }
      selectedTab = .library; librarySection = .files; libraryPath = [.projectSource(id)]
      return id
    } catch { importErrorMessage = error.localizedDescription; return nil }
  }
}
