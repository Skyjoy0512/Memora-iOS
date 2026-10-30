import Foundation

enum DocumentPDFError: LocalizedError {
  case layoutFailed
  case writeFailed
  case companyTemplateUnsupported

  var errorDescription: String? {
    switch self {
    case .layoutFailed: "本文をページに配置できませんでした。資料は変更されていません。"
    case .writeFailed: "PDFを保存できませんでした。空き容量を確認して、もう一度お試しください。"
    case .companyTemplateUnsupported: "会社ファイルの原本を含むPDF変換には対応していません。元の会社ファイルで共有してください。"
    }
  }
}
