import Foundation

enum CompanyPresentationBackgroundChecks {
  static func run(source: Data) throws {
    var analyzer = try CompanyPresentationAnalyzer(data: source)
    let master = try analyzer.measure().masters[0]
    let white = "<a:solidFill><a:srgbClr val='FFFFFF'/></a:solidFill>"
    func background(_ contents: String) -> String { "<p:bg><p:bgPr>\(contents)</p:bgPr></p:bg>" }
    let supported = [
      "", background(white), background(white + "<a:effectLst/>"),
      background("<a:solidFill><a:schemeClr val='bg1'/></a:solidFill>"),
      "<p:bg> \n<p:bgPr> \n<a:solidFill> \n<a:srgbClr val='FFFFFF'> \n</a:srgbClr> \n</a:solidFill> \n<a:effectLst> \n</a:effectLst> \n</p:bgPr> \n</p:bg>"
    ]
    let unsupported = [
      background(white + "<a:solidFill><a:srgbClr val='000000'/></a:solidFill>"),
      background(white + white),
      background(white + "<a:effectLst/><a:effectLst/>"),
      background("<a:effectLst/>" + white),
      background(white + "<a:gradFill/>"),
      background(white + "<a:effectDag/>"),
      background(white + "<a:effectLst><a:outerShdw/></a:effectLst>"),
      background(white + "<a:effectLst unexpected='1'/>"),
      background(white + "<a:effectLst>ignored text</a:effectLst>"),
      background(white + "<effectLst xmlns='urn:wrong'/>"),
      background("<a:solidFill unexpected='1'><a:srgbClr val='FFFFFF'/></a:solidFill>"),
      background("<a:solidFill>ignored text<a:srgbClr val='FFFFFF'/></a:solidFill>"),
      background("<a:solidFill><a:srgbClr val='FFFFFF'>ignored text</a:srgbClr></a:solidFill>"),
      background("<a:solidFill><a:srgbClr val='FFFFFF' unexpected='1'/></a:solidFill>"),
      background("<a:solidFill><a:srgbClr val='FFFFFF'><a:alpha val='0'/></a:srgbClr></a:solidFill>"),
      background("<a:solidFill><a:srgbClr val='FFFFFF'/><a:srgbClr val='000000'/></a:solidFill>"),
      background("<a:solidFill><srgbClr xmlns='urn:wrong' val='FFFFFF'/></a:solidFill>"),
      background("<a:solidFill><a:schemeClr val='bg2'/></a:solidFill>"),
      background("<a:solidFill><a:srgbClr val='000000'/></a:solidFill>"),
      background("<a:solidFill/>"), background("<a:effectLst/>"), background(""),
      background(white + "ignored text"),
      "<p:bg>ignored text<p:bgPr>\(white)</p:bgPr></p:bg>",
      "<p:bg unexpected='1'><p:bgPr>\(white)</p:bgPr></p:bg>",
      "<p:bg><p:bgPr unexpected='1'>\(white)</p:bgPr></p:bg>",
      "<p:bg><p:bgPr>\(white)</p:bgPr><p:bgPr>\(white)</p:bgPr></p:bg>",
      "<p:bg><p:bgRef idx='1001'><a:schemeClr val='bg1'/></p:bgRef></p:bg>",
      background(white) + background(white)
    ]
    let document = MemoraDocument(title: "背景検査", kind: .slides, slides: [PresentationExample.slide(.b01)])
    let paths = ["ppt/slideMasters/slideMaster1.xml", "ppt/slideLayouts/slideLayout1.xml"]
    for path in paths {
      for (index, value) in supported.enumerated() {
        let package = try replacingBackground(source, path: path, background: value)
        var archive = try OfficeArchiveReader(data: package)
        _ = try CompanyPresentationDecorationReader.elements(archive.read(path), master: master)
        let preview = try CompanyPresentationPreview.make(document: document, template: package)
        precondition(preview.pages.count == 1, "Supported background failed: \(path) #\(index)")
      }
      for (index, value) in unsupported.enumerated() {
        let package = try replacingBackground(source, path: path, background: value)
        var archive = try OfficeArchiveReader(data: package)
        do {
          _ = try CompanyPresentationDecorationReader.elements(archive.read(path), master: master)
          preconditionFailure("Unsupported background silently accepted by reader: \(path) #\(index)")
        } catch CompanyPresentationPreview.Failure.unsupported {}
        do {
          _ = try CompanyPresentationPreview.make(document: document, template: package)
          preconditionFailure("Unsupported background silently accepted by preview: \(path) #\(index)")
        } catch CompanyPresentationPreview.Failure.unsupported {
        } catch is CompanyPresentationExporter.Failure {}
      }
    }
    print("Company backgrounds: \(supported.count * paths.count) supported reader/package previews, \(unsupported.count * paths.count) typed reader refusals and package preview refusals; master + layout; no malformed-background PDF generated")
  }

  private static func replacingBackground(_ source: Data, path: String, background: String) throws -> Data {
    try CompanyPresentationPreviewChecks.changing(source) { part, text in
      guard part == path else { return text }
      var value = text
      if let start = value.range(of: "<p:bg>"), let end = value.range(of: "</p:bg>", range: start.upperBound..<value.endIndex) {
        value.removeSubrange(start.lowerBound..<end.upperBound)
      }
      let insertion = value.range(of: "<p:spTree>")!.lowerBound
      value.insert(contentsOf: background, at: insertion)
      return value
    }
  }
}
