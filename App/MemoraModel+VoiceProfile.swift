import Foundation

extension MemoraModel {
  func reloadSpeakerProfile() {
    do {
      speakerProfile = try speakerProfileReference.flatMap { try SpeakerProfileStore.load($0.id) }
      if let reference = speakerProfileReference { speakerProfile?.isEnabled = reference.isEnabled }
    }
    catch {
      speakerProfile = nil
      announce("声のプロフィールを読み込めません。ロック解除後に開き直すか、再登録してください。")
    }
  }

  func enrollCurrentSpeaker(fileURLs: [URL], consentAt: Date, keepsSample: Bool,
    onProgress: (Int, Int) -> Void) async throws {
    guard !isEnrollingSpeaker, speakerAnalysisIDs.isEmpty else { throw SpeakerProcessingFailure.busy }
    guard !isRestoring, isStoreWritable(), !isRecording, !isPreparingCapture,
          (1...VoiceEnrollmentBuilder.maximumSamples).contains(fileURLs.count),
          Set(fileURLs.map(\.standardizedFileURL)).count == fileURLs.count,
          fileURLs.allSatisfy({ VoiceProfileFiles.resolve($0.lastPathComponent)?.standardizedFileURL == $0.standardizedFileURL }) else {
      throw SpeakerProcessingFailure.storageFailure
    }
    isEnrollingSpeaker = true
    defer { isEnrollingSpeaker = false }
    let revision = speakerEnrollmentRevision
    let service: any SpeakerDiarizationService = FluidSpeakerDiarizationService.shared
    var results: [SpeakerAnalysisResult] = []
    var qualities: [VoiceQualityMetadata] = []
    for (index, fileURL) in fileURLs.enumerated() {
      try Task.checkCancellation()
      onProgress(index + 1, fileURLs.count)
      do {
        let result = try await service.analyze(fileURL)
        let quality = try await VoiceSampleAnalyzer.shared.assess(fileURL, intervals: result.intervals)
        results.append(result)
        qualities.append(quality)
      } catch {
        if Task.isCancelled { throw CancellationError() }
        throw VoiceEnrollmentFailure(sampleNumber: index + 1, reason: error.localizedDescription)
      }
    }
    try Task.checkCancellation()
    guard revision == speakerEnrollmentRevision, !isRestoring, isStoreWritable(), !isRecording, !isPreparingCapture else {
      throw SpeakerProcessingFailure.storageFailure
    }
    let profile = try VoiceEnrollmentBuilder.profile(results: results, qualities: qualities, consentAt: consentAt)
    try SpeakerProfileStore.save(profile)
    let reference = SpeakerProfileReference(profile)
    guard persistNow([reference], forKey: StorageKey.speakerProfile) else {
      throw SpeakerProcessingFailure.storageFailure
    }
    SpeakerProfileStore.activate()
    speakerProfileReference = reference
    speakerProfile = profile
    do {
      try SpeakerProfileStore.removeUnused(keeping: profile.id)
      if keepsSample, let latest = fileURLs.last, let quality = qualities.last {
        guard saveVoiceProfile(fileURL: latest, duration: quality.sampleDuration) else {
          throw SpeakerProcessingFailure.storageFailure
        }
      } else if voiceProfile != nil, !removeVoiceProfile() {
        throw SpeakerProcessingFailure.storageFailure
      }
      for fileURL in fileURLs where !keepsSample || fileURL != fileURLs.last {
        try VoiceProfileFiles.remove(fileURL.lastPathComponent)
      }
    } catch {
      persistenceFailureMessage = "声の特徴量は登録しましたが、登録用音声の保存・削除または旧特徴量の削除を完了できませんでした。設定から削除・再登録してください。"
      announce(persistenceFailureMessage ?? "声の保存状態を確認してください。")
      return
    }
    announce("声の特徴量をこの端末に登録しました。自動の本人確定は実機検証待ちです。")
  }

  func setSpeakerProfileEnabled(_ enabled: Bool) {
    guard !isRestoring, isStoreWritable(), var profile = speakerProfile else { return }
    profile.isEnabled = enabled
    profile.updatedAt = .now
    do {
      try SpeakerProfileStore.save(profile)
      let reference = SpeakerProfileReference(profile)
      guard persistNow([reference], forKey: StorageKey.speakerProfile) else { throw SpeakerProcessingFailure.storageFailure }
      speakerEnrollmentRevision = UUID()
      speakerProfileReference = reference
      speakerProfile = profile
    } catch { announce("声の設定を保存できませんでした。") }
  }

  func removeSpeakerEmbedding() -> Bool {
    guard !isRestoring, isStoreWritable() else { return false }
    speakerEnrollmentRevision = UUID()
    speakerProfile = nil
    do {
      try SpeakerProfileStore.delete()
      guard persistNow([SpeakerProfileReference](), forKey: StorageKey.speakerProfile) else {
        throw SpeakerProcessingFailure.storageFailure
      }
      speakerProfileReference = nil
      return true
    } catch {
      announce("声の照合を無効にしましたが、保存データの削除を完了できませんでした。もう一度削除してください。")
      return false
    }
  }
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
