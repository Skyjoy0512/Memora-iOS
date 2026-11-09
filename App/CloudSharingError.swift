import Foundation
import Observation

enum CloudSharingError: LocalizedError, Equatable {
  case saveFailed
  case cleanupFailed

  var errorDescription: String? {
    switch self {
    case .saveFailed:
      "共有を作成できませんでした。iCloudの状態を確認してください。"
    case .cleanupFailed:
      "共有の準備は中止しましたが、iCloud上の一時データを削除できませんでした。通信環境とiCloudの状態を確認してください。"
    }
  }
}
