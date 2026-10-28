import Foundation

enum CompanyPresentationColorChecks {
  static func run(source: Data) throws {
    var analyzer = try CompanyPresentationAnalyzer(data: source)
    let master = try analyzer.measure().masters[0]
    func color(_ body: String, attributes: String = "") throws -> String {
      let xml = try OfficeXMLDocument(data: Data("<a:solidFill xmlns:a='http://schemas.openxmlformats.org/drawingml/2006/main' \(attributes)>\(body)</a:solidFill>".utf8))
      return try CompanyPresentationColor.decorationFill(0, in: xml, master: master)
    }
    let cases: [(String, String)] = [
      ("<a:schemeClr val='accent1'/>", "005A50"),
      ("<a:srgbClr val='aBcDeF'/>", "ABCDEF"),
      ("<a:schemeClr val='accent1'><a:lumMod val='50000'/></a:schemeClr>", "002D28"),
      ("<a:srgbClr val='005A50'><a:lumMod val='20000'/><a:lumOff val='80000'/></a:srgbClr>", "ABFFF6"),
      ("<a:srgbClr val='000000'><a:lumOff val='90000'/><a:lumMod val='50000'/></a:srgbClr>", "737373"),
      ("<a:srgbClr val='000000'><a:lumMod val='50000'/><a:lumOff val='90000'/></a:srgbClr>", "E6E6E6"),
      ("<a:srgbClr val='FFFFFF'><a:lumOff val='50000'/><a:lumMod val='50000'/></a:srgbClr>", "808080"),
      ("<a:srgbClr val='010101'><a:lumMod val='50000'/><a:lumMod val='50000'/></a:srgbClr>", "000000"),
      ("<a:srgbClr val='804020'><a:lumMod val='50000'/><a:lumMod val='50000'/></a:srgbClr>", "201008"),
      ("<a:srgbClr val='005A50'><a:lumMod val='0'/></a:srgbClr>", "000000"),
      ("<a:srgbClr val='005A50'><a:lumOff val='100000'/></a:srgbClr>", "FFFFFF"),
      ("<a:srgbClr val='005A50'><a:lumMod val='100000'/><a:lumOff val='0'/><a:lumMod val='100000'/><a:lumOff val='0'/></a:srgbClr>", "005A50")
    ]
    for (body, expected) in cases {
      let actual = try color(body)
      precondition(actual == expected, "HSL transform mismatch: \(body), got \(actual), expected \(expected)")
    }
    let invalidSteps = [
      "<a:alpha val='50000'/>", "<a:shade val='50000'/>", "<a:tint val='50000'/>", "<a:gamma/>",
      "<a:lumMod/>", "<a:lumMod val='-1'/>", "<a:lumOff val='100001'/>", "<a:lumMod val='999999999999999999'/>",
      "<a:lumMod val='50%'/>", "<a:lumMod val='50000.0'/>", "<a:lumMod val='NaN'/>", "<a:lumMod val=''/>",
      "<a:lumMod val='５００００'/>", "<a:lumMod val='+50000'/>", "<a:lumMod val=' 50000'/>",
      "<a:lumMod val='50000' unexpected='1'/>", "<a:lumMod val='50000'>ignored text</a:lumMod>",
      "<a:lumMod val='50000'><a:lumOff val='10000'/></a:lumMod>", "<lumMod xmlns='urn:wrong' val='50000'/>",
      String(repeating: "<a:lumMod val='100000'/>", count: 5)
    ]
    var invalidColors = invalidSteps.map { "<a:srgbClr val='005A50'>\($0)</a:srgbClr>" }
    invalidColors += [
      "<a:schemeClr val='missing'/>", "<a:sysClr val='windowText' lastClr='000000'/>",
      "<a:srgbClr val='FFFFFF' unexpected='1'/>", "<a:srgbClr val='FFFFFF'>ignored text</a:srgbClr>",
      "<a:srgbClr val='FFFFFF'/><a:srgbClr val='000000'/>", "<a:srgbClr val='FFFFFF'/>ignored text",
      "<srgbClr xmlns='urn:wrong' val='FFFFFF'/>", "<a:srgbClr val='FFFFFG'/>"
    ]
    for body in invalidColors {
      do { _ = try color(body); preconditionFailure("Unsupported color silently accepted: \(body)") }
      catch CompanyPresentationPreview.Failure.unsupported {}
    }
    do { _ = try color("<a:srgbClr val='FFFFFF'/>", attributes: "unexpected='1'"); preconditionFailure("Unknown fill attributes accepted") }
    catch CompanyPresentationPreview.Failure.unsupported {}
    for value in [Double.nan, .infinity, -0.1, 1.1] {
      do { _ = try CompanyPresentationColor.tint("005A50", multiplier: value, offset: 0); preconditionFailure("Invalid multiplier accepted") }
      catch CompanyPresentationPreview.Failure.unsupported {}
      do { _ = try CompanyPresentationColor.tint("005A50", multiplier: 1, offset: value); preconditionFailure("Invalid offset accepted") }
      catch CompanyPresentationPreview.Failure.unsupported {}
    }
    print("Company decoration colors: \(cases.count) known HSL results, \(invalidColors.count + 1) unsupported XML refusals, 8 invalid numeric refusals; ordered/clamped transforms without intermediate RGB quantization; no Office rendering certification")
  }
}
