import Foundation

/// Charts are editable vector shapes, avoiding Quick Look's missing native-chart path.
/// Office's chart-data editor is not available for these shapes; data is edited in Memora.
enum PresentationOOXML {
  static func shapes(_ elements: [PresentationElement]) -> String {
    elements.map { e in
      if e.kind == .line, let first = e.points.first, let last = e.points.last {
        let flip = (first.x > last.x ? " flipH=\"1\"" : "") + (first.y > last.y ? " flipV=\"1\"" : "")
        let frame = "<a:xfrm\(flip)><a:off x=\"\(emu(e.x))\" y=\"\(emu(e.y))\"/><a:ext cx=\"\(max(1, emu(e.width)))\" cy=\"\(max(1, emu(e.height)))\"/></a:xfrm>"
        return "<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"\(e.id + 2)\" name=\"Memora connector \(e.id)\"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr>\(frame)<a:prstGeom prst=\"line\"><a:avLst/></a:prstGeom><a:ln w=\"12700\"><a:solidFill><a:srgbClr val=\"\(e.color)\"/></a:solidFill></a:ln></p:spPr><p:style><a:lnRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:lnRef><a:fillRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:fillRef><a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef><a:fontRef idx=\"minor\"><a:schemeClr val=\"tx1\"/></a:fontRef></p:style></p:cxnSp>"
      }
      let frame = transform(x: e.x, y: e.y, width: e.width, height: e.height)
      let fill = e.fill.map { "<a:solidFill><a:srgbClr val=\"\($0)\"/></a:solidFill>" } ?? "<a:noFill/>"
      var geometry: String
      switch e.kind {
      case .line, .polygon:
        let w = max(1, emu(e.width)), h = max(1, emu(e.height))
        let points = e.points.enumerated().map { i, p in
          "<a:\(i == 0 ? "moveTo" : "lnTo")><a:pt x=\"\(emu(p.x - e.x))\" y=\"\(emu(p.y - e.y))\"/></a:\(i == 0 ? "moveTo" : "lnTo")>"
        }.joined()
        geometry = "<a:custGeom><a:avLst/><a:gdLst/><a:ahLst/><a:cxnLst/><a:rect l=\"0\" t=\"0\" r=\"r\" b=\"b\"/><a:pathLst><a:path w=\"\(w)\" h=\"\(h)\" fill=\"\(e.kind == .line ? "none" : "norm")\">\(points)\(e.kind == .polygon ? "<a:close/>" : "")</a:path></a:pathLst></a:custGeom>"
      default:
        geometry = "<a:prstGeom prst=\"\(e.kind == .ellipse ? "ellipse" : "rect")\"><a:avLst/></a:prstGeom>"
      }
      let stroke = e.kind == .line ? "<a:ln w=\"12700\"><a:solidFill><a:srgbClr val=\"\(e.color)\"/></a:solidFill></a:ln>" : "<a:ln><a:noFill/></a:ln>"
      var body = ""
      if e.kind == .text {
        let sz = Int(e.fontSize * 100), lineHeight = Int(e.fontSize * 130)
        let paragraphs = PresentationText.lines(e).map { line in
          "<a:p><a:pPr><a:lnSpc><a:spcPts val=\"\(lineHeight)\"/></a:lnSpc><a:buNone/></a:pPr><a:r><a:rPr lang=\"ja-JP\" sz=\"\(sz)\" b=\"\(e.bold ? 1 : 0)\"><a:solidFill><a:srgbClr val=\"\(e.color)\"/></a:solidFill><a:latin typeface=\"\(PresentationTheme.font)\"/><a:ea typeface=\"\(PresentationTheme.font)\"/></a:rPr><a:t xml:space=\"preserve\">\(escape(line))</a:t></a:r><a:endParaRPr lang=\"ja-JP\" sz=\"\(sz)\"/></a:p>"
        }.joined()
        body = "<p:txBody><a:bodyPr wrap=\"none\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"><a:noAutofit/></a:bodyPr><a:lstStyle/>\(paragraphs)</p:txBody>"
      }
      return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(e.id + 2)\" name=\"Memora \(e.kind.rawValue) \(e.id)\"/><p:cNvSpPr\(e.kind == .text ? " txBox=\"1\"" : "")/><p:nvPr/></p:nvSpPr><p:spPr>\(frame)\(geometry)\(fill)\(stroke)</p:spPr>\(body)</p:sp>"
    }.joined()
  }

  private static func emu(_ value: Double) -> Int { Int((value * 12_700).rounded()) }
  private static func transform(x: Double, y: Double, width: Double, height: Double) -> String {
    "<a:xfrm><a:off x=\"\(emu(x))\" y=\"\(emu(y))\"/><a:ext cx=\"\(max(1, emu(width)))\" cy=\"\(max(1, emu(height)))\"/></a:xfrm>"
  }
  private static func escape(_ value: String) -> String {
    String(value.unicodeScalars.filter { $0 == "\t" || $0 == "\n" || $0 == "\r" || $0.value >= 0x20 && $0.value != 0xFFFE && $0.value != 0xFFFF })
      .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }
}
