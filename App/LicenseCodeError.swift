import Foundation

enum LicenseCodeError: LocalizedError {
  case malformed
  case invalidSignature
  case expired
  case verifierMissing
  case storage

  var errorDescription: String? {
    switch self {
    case .malformed: "コードの形式が正しくありません。MEMORA- から始まるコードを、そのまま貼り付けてください。"
    case .invalidSignature: "このコードは有効ではありません。発行元に確認してください。"
    case .expired: "このライセンスは期限が切れています。"
    case .verifierMissing: "このビルドにはライセンスの検証鍵が設定されていません。"
    case .storage: "ライセンスを端末に保存できませんでした。現在のライセンスは変更していません。端末のロック状態などを確認して、もう一度お試しください。"
    }
  }
}
