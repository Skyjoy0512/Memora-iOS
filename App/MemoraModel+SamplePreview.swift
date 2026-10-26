import Foundation

extension MemoraModel {
  /// Replaying onboarding must never reset the person's collections.
  @discardableResult
  func openSummarizedAudioSample() -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable() else { return false }
    if !meetings.contains(where: { $0.id == SummarizedAudioSample.id }) {
      let candidate = [SummarizedAudioSample.make()] + meetings
      guard persistBatch({ [(key: StorageKey.meetings, data: try RecordStore.encoded(candidate))] }) else { return false }
      meetings = candidate
    }
    selectedTab = .library
    librarySection = .files
    libraryPath = [.meeting(SummarizedAudioSample.id)]
    return true
  }
}
