import Foundation

extension MemoraModel {
  @discardableResult
  func addRecordingMarker() -> Bool {
    guard isRecording, !isRecordingPaused, !isSavingCapture,
          let timestamp = recorder.recordedDuration else { return false }
    guard let markers = RecordingMarker.adding(at: timestamp, to: recordingMarkers) else {
      announce("直前のマークから1秒以上あけて追加してください")
      return false
    }
    guard saveRecordingMarkers(markers) else { return false }
    announce("\(MemoraFormat.duration(timestamp))に重要マークを追加しました")
    return true
  }

  func removeRecordingMarker(_ id: UUID) {
    guard isRecording, !isSavingCapture, recordingMarkers.contains(where: { $0.id == id }) else { return }
    _ = saveRecordingMarkers(recordingMarkers.filter { $0.id != id })
  }

  func removeMeetingRecordingMarker(meetingID: UUID, markerID: UUID) {
    guard let index = meetings.firstIndex(where: { $0.id == meetingID }),
          meetings[index].recordingMarkers.contains(where: { $0.id == markerID }) else { return }
    var candidate = meetings
    candidate[index].recordingMarkers.removeAll { $0.id == markerID }
    guard persistNow(candidate, forKey: StorageKey.meetings) else { return }
    meetings = candidate
    announce("重要マークを削除しました")
  }

  private func saveRecordingMarkers(_ markers: [RecordingMarker]) -> Bool {
    guard var draft = recordingDraft else {
      recordingErrorMessage = "録音の保存準備ができていないため、重要マークを追加できません。録音を終了して保存してください。"
      return false
    }
    draft.markers = markers.isEmpty ? nil : markers
    draft.title = recordingTitle
    draft.note = recordingNote
    guard persistNow(draft, forKey: StorageKey.recordingDraft) else { return false }
    recordingDraft = draft
    recordingMarkers = markers
    return true
  }
}
