import Foundation

@main
struct CollectionSearchChecks {
  static func main() {
    precondition(CollectionSearch.matches("  ", fields: []))
    precondition(CollectionSearch.matches("mori design", fields: ["Mori", "Design team"]))
    precondition(CollectionSearch.matches("ｍｏｒｉ", fields: ["Mori"]))
    precondition(CollectionSearch.matches("cafe", fields: ["Café"]))
    precondition(CollectionSearch.matches("研究 相談", fields: ["週報", "研究計画の相談をした"]))
    precondition(!CollectionSearch.matches("研究 未確認", fields: ["週報", "研究計画の相談をした"]))
    precondition(!CollectionSearch.matches("missing", fields: []))
    precondition(!CollectionSearch.matches("across", fields: ["acr", "oss"]))
    precondition(ToolsCatalogSearch.matches("Google Drive", fields: ["Google", "Drive"]))
    print("CollectionSearchChecks: passed (empty query, multi-field AND, Japanese, width/case/diacritics, no false cross-field substring, Tools compatibility)")
  }
}
