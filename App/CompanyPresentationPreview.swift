import Foundation

/// Only the newly authored pages. Original template pages are never approximated.
struct CompanyPresentationPreview: Sendable {
  var pages: [SlidePage]
  var originalPageCount: Int
  var layoutPart: String

  enum Failure: LocalizedError {
    case unsupported, stale
    var errorDescription: String? {
      switch self {
      case .unsupported: String(localized: "会社書式の追加ページを描画できません。画像・文字装飾・輪郭線・複雑な図形などには未対応です。省略したPDFは作成しません。会社PPTXを確認してください。")
      case .stale: String(localized: "資料・会社書式・ワークスペースが変更されました。開き直して確認してください。")
      }
    }
  }

  static func make(document: MemoraDocument, template: Data) throws -> Self {
    guard document.hasValidRevisions, Set(document.slides.map(\.id)).count == document.slides.count else { throw Failure.unsupported }
    let profile = try CompanyPresentationExporter.validatedProfile(document: document, template: template)
    // Validate the actual package through the same export path before promising a preview.
    _ = try CompanyPresentationExporter.data(for: document, template: template)
    let selection = try CompanyPresentationExporter.choose(profile: profile, document: document)
    var archive = try OfficeArchiveReader(data: template)
    let decorations = try CompanyPresentationDecorationReader.elements(archive.read(selection.master.id), master: selection.master)
      + CompanyPresentationDecorationReader.elements(archive.read(selection.layout.id), master: selection.master)
    let pages = try document.slides.map { slide -> SlidePage in
      try Task.checkCancellation()
      let painted = try CompanyPresentationExporter.themedElements(slide, theme: selection.master.theme!).map { element in
        var result = element
        guard let role = CompanyPresentationExporter.palette[element.color] else { throw Failure.unsupported }
        result.color = try CompanyPresentationColor.resolve(role, master: selection.master, lightened: [PresentationTheme.rule, "DBEAFE"].contains(element.color))
        if let fill = element.fill {
          guard let role = CompanyPresentationExporter.palette[fill] else { throw Failure.unsupported }
          result.fill = try CompanyPresentationColor.resolve(role, master: selection.master, lightened: [PresentationTheme.rule, "DBEAFE"].contains(fill))
        }
        return result
      }
      let elements = (decorations + painted).enumerated().map { index, element in var value = element; value.id = index; return value }
      return .init(sourceID: slide.id, fragment: 0, titleLines: [slide.title], bullets: [], notes: slide.notes,
        isCover: false, elements: elements, readingText: slide.composition!.readingText)
    }
    return .init(pages: pages, originalPageCount: profile.slideCount, layoutPart: selection.layout.id)
  }
}
