import Foundation

extension MemoraModel {
  func beginBackupRestore() throws {
    try Task.checkCancellation()
    guard currentTeamID == nil else { throw BackupPackage.BackupError.personalWorkspaceRequired }
    guard !isStoreProtected else { throw BackupPackage.BackupError.storeProtected }
    guard !isRecording, !isSavingCapture, recordingDraft == nil else {
      throw BackupPackage.BackupError.busy
    }
    guard !isRestoring, !isImporting, !isImportingShareInbox,
          pendingImportURLs.isEmpty, inFlightImportURLs.isEmpty, projectSourceProcessingIDs.isEmpty,
          !isAIChatResponding, residentJobs.isEmpty, projectChatJobs.isEmpty, webResearchJobs.isEmpty,
          processing.activeIDs.isEmpty, speakerAnalysisIDs.isEmpty, !isEnrollingSpeaker else {
      throw BackupPackage.BackupError.busy
    }
    guard isEmpty else { throw BackupPackage.BackupError.notEmpty }

    // Even a failed restore invalidates work captured before it, so a picker
    // cannot silently resume into restored data once isRestoring becomes false.
    aiWorkspaceGeneration = UUID()
    isRestoring = true
  }
}
