import Foundation
import Observation

enum CloudSharingError: LocalizedError {
  case saveFailed

  var errorDescription: String? {
    switch self {
    case .saveFailed:
      "共有を作成できませんでした。iCloudの状態を確認してください。"
    }
  }
}
