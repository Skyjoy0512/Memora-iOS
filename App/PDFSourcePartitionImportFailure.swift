import Foundation

enum PDFSourcePartitionImportFailure: LocalizedError {
  case privacyChanged

  var errorDescription: String? {
    "同じ分割PDFが異なるプライバシー設定で保存されています。既存の資料と元PDFの設定を確認してください。"
  }
}
