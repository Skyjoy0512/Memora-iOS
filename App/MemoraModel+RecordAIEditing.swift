import Foundation

extension MemoraModel {
  func applyRecordAIEdit(_ request: RecordAIEdit, replacement: String) -> Bool {
    guard request.isCurrent(in: self),
          !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    return updateMeeting(request.recordID) { $0[keyPath: request.field.value] = replacement }
  }
}
