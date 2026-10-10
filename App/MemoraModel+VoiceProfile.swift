import Foundation

extension MemoraModel {
  func removeUnregisteredVoiceSamples() {
    guard !isStoreProtected else { return }
    do {
      try VoiceProfileFiles.removeUnused(keeping: voiceProfile?.fileName)
    } catch {
      persistenceFailureMessage = "未登録の音声サンプルを削除できませんでした。次回の起動時にもう一度削除します。"
    }
  }

  func saveVoiceProfile(fileURL: URL, duration: TimeInterval) -> Bool {
    guard !isRestoring, isStoreWritable(), duration.isFinite,
          duration >= VoiceEnrollmentService.minimumDuration,
          VoiceProfileFiles.resolve(fileURL.lastPathComponent)?.standardizedFileURL == fileURL.standardizedFileURL,
          FileManager.default.fileExists(atPath: fileURL.path) else { return false }
    let previous = voiceProfile
    let candidate = VoiceProfile(fileName: fileURL.lastPathComponent, duration: duration, registeredAt: .now)
    guard persistNow([candidate], forKey: StorageKey.voiceProfile) else { return false }
    voiceProfile = candidate
    if let previous, previous.fileName != candidate.fileName {
      do {
        try VoiceProfileFiles.remove(previous.fileName)
      } catch {
        persistenceFailureMessage = "新しい声は登録しましたが、以前の音声ファイルを削除できませんでした。"
      }
    }
    return true
  }

  func removeVoiceProfile() -> Bool {
    guard !isRestoring, isStoreWritable(), let previous = voiceProfile else { return false }
    guard persistNow([VoiceProfile](), forKey: StorageKey.voiceProfile) else { return false }
    do {
      try VoiceProfileFiles.remove(previous.fileName)
      voiceProfile = nil
      return true
    } catch {
      persistNow([previous], forKey: StorageKey.voiceProfile)
      persistenceFailureMessage = "音声サンプルを削除できませんでした。もう一度お試しください。"
      return false
    }
  }
}
