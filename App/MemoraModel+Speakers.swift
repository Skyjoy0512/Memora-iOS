import Foundation

extension MemoraModel {
  func analyzeSpeakers(_ id: UUID) async {
    guard !isEnrollingSpeaker, !speakerAnalysisIDs.contains(id), !processing.isActive(id), !isRestoring, isStoreWritable(),
          let record = meeting(id: id), let audioURL = record.audioURL, !record.transcript.isEmpty else { return }
    guard record.transcript.contains(where: { $0.endTime != nil }) else {
      speakerAnalysisMessages[id] = "この文字起こしには発言の終了時刻がありません。自動の話者割り当ては行いません。話者名は手動で編集できます。"
      return
    }
    let revision = ProcessingService.inputRevision(record.transcript)
    speakerAnalysisIDs.insert(id)
    speakerAnalysisMessages[id] = "端末内で話者を解析しています…"
    defer { speakerAnalysisIDs.remove(id) }
    do {
      let service: any SpeakerDiarizationService = FluidSpeakerDiarizationService.shared
      let result = try await service.analyze(audioURL)
      try Task.checkCancellation()
      guard !isRestoring, isStoreWritable(), let current = meeting(id: id), current.audioURL == audioURL,
            ProcessingService.inputRevision(current.transcript) == revision else {
        speakerAnalysisMessages[id] = "記録が変わったため解析結果は反映しませんでした。"
        return
      }
      let aligned = SpeakerTranscriptAligner.align(current.transcript, intervals: result.intervals, minimumDuration: 1)
      guard updateMeeting(id, change: { $0.transcript = aligned }),
            await persistNowAsync(meetings, forKey: StorageKey.meetings) else {
        speakerAnalysisMessages[id] = "解析しましたが、話者情報の保存を完了できませんでした。原音声・原文は保持しています。保存状態を確認して再試行してください。"
        return
      }
      let matched = aligned.filter { $0.identificationStatus == .anonymous }.count
      var message = "\(matched)件の発言に匿名の話者を割り当てました。手動で確認・修正できます。"
      if let profile = speakerProfile, profile.isEnabled {
        do {
          let similarities = try SpeakerIdentificationService.similarities(profile: profile, result: result)
          if !similarities.isEmpty {
            message += " 登録した声との類似度を計算しましたが、実機で本人判定の基準を検証するまでは『自分』と自動確定しません。"
          }
        } catch {
          message += " 声のモデルが変わったため再登録が必要です。"
        }
      }
      speakerAnalysisMessages[id] = message
    } catch is CancellationError {
      speakerAnalysisMessages[id] = "解析を中断しました。原音声・文字起こしは保持しています。"
    } catch {
      speakerAnalysisMessages[id] = "話者解析を完了できませんでした。\(error.localizedDescription)"
    }
  }
}
