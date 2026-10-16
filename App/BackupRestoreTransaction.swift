import Foundation

/// Files remain reversible until the caller commits every record in one store transaction.
enum BackupRestoreTransaction {
  @MainActor
  static func restore(from package: URL, commit: (BackupPackage.Manifest) throws -> Void) async throws {
    try Task.checkCancellation()
    let preparation = Task.detached(priority: .userInitiated) {
      let manifest = try BackupPackage.read(from: package)
      let media = try BackupPackage.install(mediaFrom: package, manifest: manifest)
      do {
        let workspace = try ProjectWorkspaceBackup.install(manifest.projectSources ?? [], from: package,
          additionalNames: manifest.additionalWorkspaceFiles)
        return (manifest, media, workspace)
      } catch {
        BackupPackage.removeInstalledMedia(media)
        throw error
      }
    }
    let (manifest, media, workspace) = try await withTaskCancellationHandler {
      try await preparation.value
    } onCancel: {
      preparation.cancel()
    }
    var committed = false
    defer {
      if !committed {
        BackupPackage.removeInstalledMedia(media)
        ProjectWorkspaceBackup.remove(workspace)
      }
    }
    try Task.checkCancellation()
    try commit(manifest)
    committed = true
  }
}
