import Foundation

/// Reject unknown artwork instead of silently dropping a company's identity.
enum CompanyPresentationDecorationReader {
  private static let p: Set<String> = ["http://schemas.openxmlformats.org/presentationml/2006/main"]
  private static let a: Set<String> = ["http://schemas.openxmlformats.org/drawingml/2006/main"]

  static func elements(_ bytes: Data, master: CompanyPresentationProfile.Master) throws -> [PresentationElement] {
    let xml = try OfficeXMLDocument(data: bytes)
    guard xml.matches(0, "sldMaster", namespaces: p) || xml.matches(0, "sldLayout", namespaces: p),
          xml.nodes[0].attributes.keys.allSatisfy({ ["preserve", "type", "matchingName"].contains($0) }),
          xml.nodes[0].children.allSatisfy({ p.contains(xml.nodes[$0].namespace) && ["cSld", "clrMap", "clrMapOvr", "sldLayoutIdLst", "txStyles"].contains(xml.nodes[$0].name) }),
          xml.children(0, named: "cSld", namespaces: p).count == 1,
          let common = xml.children(0, named: "cSld", namespaces: p).first,
          xml.nodes[common].children.allSatisfy({ p.contains(xml.nodes[$0].namespace) && ["bg", "spTree"].contains(xml.nodes[$0].name) }),
          xml.children(common, named: "spTree", namespaces: p).count == 1,
          let tree = xml.children(common, named: "spTree", namespaces: p).first else { throw CompanyPresentationPreview.Failure.unsupported }
    guard xml.children(common, named: "bg", namespaces: p).count <= 1 else { throw CompanyPresentationPreview.Failure.unsupported }
    for background in xml.children(common, named: "bg", namespaces: p) {
      try validateBackground(background, in: xml)
    }
    for override in xml.children(0, named: "clrMapOvr", namespaces: p) {
      guard xml.nodes[override].children.count == 1,
            xml.matches(xml.nodes[override].children[0], "masterClrMapping", namespaces: a) else { throw CompanyPresentationPreview.Failure.unsupported }
    }
    var output: [PresentationElement] = []
    for child in xml.nodes[tree].children {
      if xml.matches(child, "nvGrpSpPr", namespaces: p) { continue }
      if xml.matches(child, "grpSpPr", namespaces: p) {
        guard xml.nodes[child].children.allSatisfy({ xml.matches($0, "xfrm", namespaces: a) && xml.nodes[$0].attributes.isEmpty && xml.nodes[$0].children.allSatisfy {
          a.contains(xml.nodes[$0].namespace) && ["off", "ext", "chOff", "chExt"].contains(xml.nodes[$0].name) && xml.nodes[$0].attributes.values.allSatisfy { $0 == "0" }
        } }) else { throw CompanyPresentationPreview.Failure.unsupported }
        continue
      }
      guard xml.matches(child, "sp", namespaces: p),
            xml.nodes[child].attributes.isEmpty,
            xml.nodes[child].children.count == 2,
            xml.nodes[child].children.allSatisfy({ xml.matches($0, "nvSpPr", namespaces: p) || xml.matches($0, "spPr", namespaces: p) }),
            xml.descendants(child, named: "ph", namespaces: p).isEmpty,
            let properties = xml.children(child, named: "spPr", namespaces: p).first,
            xml.nodes[properties].attributes.isEmpty, xml.nodes[properties].children.count == 4,
            ["xfrm", "prstGeom", "solidFill", "ln"].allSatisfy({ xml.children(properties, named: $0, namespaces: a).count == 1 }),
            let transform = xml.children(properties, named: "xfrm", namespaces: a).first,
            xml.nodes[transform].attributes.isEmpty, xml.nodes[transform].children.count == 2,
            let origin = xml.children(transform, named: "off", namespaces: a).first,
            let extent = xml.children(transform, named: "ext", namespaces: a).first,
            let x = Double(xml.nodes[origin].attributes["x"] ?? ""), let y = Double(xml.nodes[origin].attributes["y"] ?? ""),
            let w = Double(xml.nodes[extent].attributes["cx"] ?? ""), let h = Double(xml.nodes[extent].attributes["cy"] ?? ""),
            [x,y,w,h].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000_000 }), w > 0, h > 0,
            let geometry = xml.children(properties, named: "prstGeom", namespaces: a).first,
            let kind = xml.nodes[geometry].attributes["prst"], ["rect", "ellipse"].contains(kind),
            xml.nodes[geometry].attributes.count == 1,
            xml.nodes[geometry].children.allSatisfy({ xml.matches($0, "avLst", namespaces: a) && xml.nodes[$0].children.isEmpty }),
            let line = xml.children(properties, named: "ln", namespaces: a).first,
            xml.nodes[line].attributes.isEmpty,
            xml.nodes[line].children.count == 1, xml.matches(xml.nodes[line].children[0], "noFill", namespaces: a),
            xml.nodes[xml.nodes[line].children[0]].attributes.isEmpty, xml.nodes[xml.nodes[line].children[0]].children.isEmpty,
            xml.nodes[properties].children.allSatisfy({ a.contains(xml.nodes[$0].namespace) && ["xfrm", "prstGeom", "solidFill", "ln"].contains(xml.nodes[$0].name) }),
            let fill = xml.children(properties, named: "solidFill", namespaces: a).first,
            xml.nodes[fill].children.count == 1 else { throw CompanyPresentationPreview.Failure.unsupported }
      guard xml.descendants(child, named: "cNvPr", namespaces: p).allSatisfy({ xml.nodes[$0].attributes.keys.allSatisfy { ["id", "name"].contains($0) } }) else { throw CompanyPresentationPreview.Failure.unsupported }
      let hex = try CompanyPresentationColor.decorationFill(fill, in: xml, master: master)
      output.append(.init(id: output.count, kind: kind == "rect" ? .rectangle : .ellipse,
        x: x / 12700, y: y / 12700, width: w / 12700, height: h / 12700, color: hex, fill: hex, checksCollision: false))
    }
    return output
  }

  private static func validateBackground(_ background: Int, in xml: OfficeXMLDocument) throws {
    func plain(_ index: Int) -> Bool {
      xml.nodes[index].attributes.isEmpty && xml.nodes[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard plain(background), xml.nodes[background].children.count == 1,
          let properties = xml.children(background, named: "bgPr", namespaces: p).first,
          plain(properties), (1...2).contains(xml.nodes[properties].children.count),
          let fill = xml.nodes[properties].children.first,
          xml.matches(fill, "solidFill", namespaces: a), plain(fill),
          xml.nodes[fill].children.count == 1 else { throw CompanyPresentationPreview.Failure.unsupported }
    // Selecting the first fill would hide a conflicting background in the source.
    if xml.nodes[properties].children.count == 2 {
      let effect = xml.nodes[properties].children[1]
      guard xml.matches(effect, "effectLst", namespaces: a), plain(effect), xml.nodes[effect].children.isEmpty else {
        throw CompanyPresentationPreview.Failure.unsupported
      }
    }
    let color = xml.nodes[xml.nodes[fill].children[0]]
    guard a.contains(color.namespace), color.children.isEmpty, color.attributes.count == 1,
          color.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          color.name == "srgbClr" && color.attributes["val"]?.uppercased() == "FFFFFF" || color.name == "schemeClr" && color.attributes["val"] == "bg1" else {
      throw CompanyPresentationPreview.Failure.unsupported
    }
  }
}
