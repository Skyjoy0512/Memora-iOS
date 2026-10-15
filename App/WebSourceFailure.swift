import Foundation

enum WebSourceFailure: LocalizedError {
  case unsafeAddress, network, certificate, timeout, invalidResponse, tooLarge, unsupportedContent, noText, redirects, status(Int)

  var errorDescription: String? {
    switch self {
    case .unsafeAddress: "接続先を安全に確認できませんでした。公開されたHTTPSページを指定してください。"
    case .network: "ページに接続できませんでした。接続と証明書を確認してから再試行してください。"
    case .certificate: "ページの証明書を確認できないため、取得を停止しました。"
    case .timeout: "ページの取得が時間上限に達しました。必要な場合は再試行してください。"
    case .invalidResponse: "ページの応答を読み取れませんでした。元のURLは保存されています。"
    case .tooLarge: "ページが取得・解析の上限を超えています。必要な部分をテキストメモとして追加してください。"
    case .unsupportedContent: "このページの形式・文字コード・圧縮には対応していません。PDFやテキストとして追加してください。"
    case .noText: "参照できる本文がありません。ログインやJavaScriptが必要なページは元のURLで確認してください。"
    case .redirects: "ページの転送が繰り返されるため取得を停止しました。元のURLは保存されています。"
    case .status(let code): "ページを取得できませんでした（HTTP \(code)）。元のURLは保存されています。"
    }
  }
}
