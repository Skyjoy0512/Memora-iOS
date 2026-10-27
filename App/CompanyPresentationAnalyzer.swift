import Foundation

/// Follows package relationships, never file-name guesses or untrusted file-system paths.
struct CompanyPresentationAnalyzer {
  private var archive: OfficeArchiveReader
  private var cache: [String: OfficeXMLDocument] = [:]
  private static let p: Set<String> = ["http://schemas.openxmlformats.org/presentationml/2006/main", "http://purl.oclc.org/ooxml/presentationml/main"]
  private static let a: Set<String> = ["http://schemas.openxmlformats.org/drawingml/2006/main", "http://purl.oclc.org/ooxml/drawingml/main"]
  private static let r: Set<String> = ["http://schemas.openxmlformats.org/package/2006/relationships"]
  private static let bases = ["http://schemas.openxmlformats.org/officeDocument/2006/relationships/", "http://purl.oclc.org/ooxml/officeDocument/relationships/"]

  init(data: Data) throws { archive = try OfficeArchiveReader(data: data) }

  mutating func measure() throws -> CompanyPresentationProfile {
    let root = try relationships(nil)
    let main = try uniqueTarget(root, kind: "officeDocument")
    let document = try xml(main, root: "presentation", namespaces: Self.p)
    guard document.children(0, named: "sldIdLst", namespaces: Self.p).count <= 1,
          document.children(0, named: "sldMasterIdLst", namespaces: Self.p).count <= 1 else { throw OfficeArchiveReader.Failure.invalid }
    guard let size = document.children(0, named: "sldSz", namespaces: Self.p).only,
          let width = positive(document.nodes[size].attributes["cx"]),
          let height = positive(document.nodes[size].attributes["cy"]) else { throw OfficeArchiveReader.Failure.invalid }
    let links = try relationships(main)
    var usage: [String: Int] = [:]
    var slideCount = 0
    var slideIDs = Set<String>()
    if let list = document.children(0, named: "sldIdLst", namespaces: Self.p).only {
      for index in document.children(list, named: "sldId", namespaces: Self.p) {
        guard slideCount < 500, let id = document.nodes[index].relationshipID,
              slideIDs.insert(id).inserted, let link = links[id], link.isType("slide") else { throw OfficeArchiveReader.Failure.invalid }
        _ = try xml(link.target, root: "sld", namespaces: Self.p)
        let layout = try uniqueTarget(relationships(link.target), kind: "slideLayout")
        usage[layout, default: 0] += 1
        slideCount += 1
      }
    }
    var masters: [CompanyPresentationProfile.Master] = []
    var layouts: [CompanyPresentationProfile.Layout] = []
    var seenMasters = Set<String>(), seenLayouts = Set<String>()
    if let list = document.children(0, named: "sldMasterIdLst", namespaces: Self.p).only {
      for index in document.children(list, named: "sldMasterId", namespaces: Self.p) {
        guard masters.count < 50, let id = document.nodes[index].relationshipID,
              let link = links[id], link.isType("slideMaster"), seenMasters.insert(link.target).inserted else { throw OfficeArchiveReader.Failure.invalid }
        let master = try xml(link.target, root: "sldMaster", namespaces: Self.p)
        let masterLinks = try relationships(link.target)
        let themeLinks = masterLinks.values.filter { $0.isType("theme") }
        guard themeLinks.count <= 1 else { throw OfficeArchiveReader.Failure.invalid }
        let theme = try themeLinks.first.map { try readTheme($0.target) }
        let measured = shapes(master, inherited: [], part: link.target)
        guard uniquePlaceholders(measured.placeholders), master.children(0, named: "sldLayoutIdLst", namespaces: Self.p).count <= 1 else { throw OfficeArchiveReader.Failure.invalid }
        let masterNotices = measured.notices
        let colorMap = master.children(0, named: "clrMap", namespaces: Self.p).first.map { master.nodes[$0].attributes } ?? [:]
        var styles: [String: Double] = [:]
        if let textStyles = master.children(0, named: "txStyles", namespaces: Self.p).first {
          for style in master.nodes[textStyles].children where Self.p.contains(master.nodes[style].namespace) {
            if let size = fontSize(master, parent: style) { styles[master.nodes[style].name] = size }
          }
        }
        let measuredMaster = CompanyPresentationProfile.Master(id: link.target, theme: theme, colorMap: colorMap,
          background: background(master), placeholders: measured.placeholders, decorations: measured.decorations, textStyles: styles)
        masters.append(measuredMaster)
        if let list = master.children(0, named: "sldLayoutIdLst", namespaces: Self.p).only {
          for child in master.children(list, named: "sldLayoutId", namespaces: Self.p) {
            guard layouts.count < 200, let id = master.nodes[child].relationshipID,
                  let layoutLink = masterLinks[id], layoutLink.isType("slideLayout"), seenLayouts.insert(layoutLink.target).inserted else { throw OfficeArchiveReader.Failure.invalid }
            let layout = try xml(layoutLink.target, root: "sldLayout", namespaces: Self.p)
            guard try uniqueTarget(relationships(layoutLink.target), kind: "slideMaster") == link.target else { throw OfficeArchiveReader.Failure.invalid }
            let measured = shapes(layout, inherited: measuredMaster.placeholders, part: layoutLink.target)
            guard uniquePlaceholders(measured.placeholders) else { throw OfficeArchiveReader.Failure.invalid }
            let common = layout.children(0, named: "cSld", namespaces: Self.p).first
            var notices = Array(Set(measured.notices + masterNotices)).sorted()
            if measured.placeholders.contains(where: { $0.frame == nil }) { notices.append("位置を確定できないプレースホルダーがあります。") }
            layouts.append(.init(id: layoutLink.target, name: String((common.flatMap { layout.nodes[$0].attributes["name"] } ?? "名称なし").prefix(200)),
              kind: layout.nodes[0].attributes["type"] ?? "未指定", masterPart: link.target, useCount: usage[layoutLink.target] ?? 0,
              background: background(layout) ?? measuredMaster.background, placeholders: measured.placeholders, decorations: measured.decorations, notices: notices))
          }
        }
      }
    }
    guard usage.keys.allSatisfy({ seenLayouts.contains($0) }) else { throw OfficeArchiveReader.Failure.invalid }
    let result = CompanyPresentationProfile(presentationPart: main, widthEMU: width, heightEMU: height, slideCount: slideCount, masters: masters,
      layouts: layouts.sorted { $0.useCount == $1.useCount ? $0.id < $1.id : $0.useCount > $1.useCount },
      notices: ["計測情報です。空白レイアウトへの追加は実行時に適合を再検査します。その他の書式再現は未対応です。", "画像の位置は計測しますが、ロゴの自動判定は行いません。", "表・グラフの個別書式、ページ番号の自動生成、最終描画は未検証です。"])
    guard result.isValid, try JSONEncoder().encode(result).count <= 512 * 1024 else { throw OfficeArchiveReader.Failure.limit }
    return result
  }

  private mutating func xml(_ part: String, root: String, namespaces: Set<String>) throws -> OfficeXMLDocument {
    try Task.checkCancellation()
    let value: OfficeXMLDocument
    if let cached = cache[part] { value = cached }
    else { value = try OfficeXMLDocument(data: archive.read(part)); cache[part] = value }
    guard value.matches(0, root, namespaces: namespaces) else { throw OfficeArchiveReader.Failure.invalid }
    return value
  }

  private struct Relationship {
    var type: String
    var target: String
    func isType(_ name: String) -> Bool { CompanyPresentationAnalyzer.bases.contains { type == $0 + name } }
  }

  private mutating func relationships(_ part: String?) throws -> [String: Relationship] {
    let directory = part.map { ($0 as NSString).deletingLastPathComponent } ?? ""
    let path = part.map { (directory.isEmpty ? "" : directory + "/") + "_rels/" + ($0 as NSString).lastPathComponent + ".rels" } ?? "_rels/.rels"
    let value = try xml(path, root: "Relationships", namespaces: Self.r)
    var result: [String: Relationship] = [:]
    for index in value.children(0, named: "Relationship", namespaces: Self.r) {
      let attrs = value.nodes[index].attributes
      guard let id = attrs["Id"], !id.isEmpty, result[id] == nil, let type = attrs["Type"],
            attrs["TargetMode"] == nil || attrs["TargetMode"] == "Internal", let raw = attrs["Target"],
            let target = resolve(raw, directory: directory), archive.contains(target) else { throw OfficeArchiveReader.Failure.invalid }
      result[id] = .init(type: type, target: target)
    }
    return result
  }

  private func uniqueTarget(_ links: [String: Relationship], kind: String) throws -> String {
    let matches = links.values.filter { $0.isType(kind) }
    guard matches.count == 1, let target = matches.first?.target else { throw OfficeArchiveReader.Failure.invalid }
    return target
  }

  private func resolve(_ raw: String, directory: String) -> String? {
    guard !raw.isEmpty, !raw.contains(":"), !raw.contains("\\"), !raw.contains("%"), !raw.contains("?"), !raw.contains("#"),
          !raw.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
    var parts = raw.hasPrefix("/") ? [] : directory.split(separator: "/").map(String.init)
    for part in raw.split(separator: "/", omittingEmptySubsequences: false).dropFirst(raw.hasPrefix("/") ? 1 : 0) {
      if part == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast() }
      else if part != "." { guard !part.isEmpty else { return nil }; parts.append(String(part)) }
    }
    return parts.isEmpty ? nil : parts.joined(separator: "/")
  }

  private func positive(_ value: String?) -> Int? {
    guard let raw = value, let result = Int(raw), (1...1_000_000_000).contains(result) else { return nil }
    return result
  }

  private func uniquePlaceholders(_ values: [CompanyPresentationProfile.Placeholder]) -> Bool {
    values.count <= 100 && Set(values.map(\.id)).count == values.count
  }

  private mutating func readTheme(_ part: String) throws -> CompanyPresentationProfile.Theme {
    let value = try xml(part, root: "theme", namespaces: Self.a)
    var colors: [String: String] = [:]
    if let scheme = value.descendants(0, named: "clrScheme", namespaces: Self.a).first {
      for slot in value.nodes[scheme].children where Self.a.contains(value.nodes[slot].namespace) {
        if let color = value.nodes[slot].children.first {
          let node = value.nodes[color]
          guard Self.a.contains(node.namespace) else { continue }
          let raw = node.name == "srgbClr" ? node.attributes["val"] : node.name == "sysClr" ? node.attributes["lastClr"] : nil
          if let raw, node.children.isEmpty, raw.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil {
            colors[value.nodes[slot].name] = raw.uppercased()
          }
        }
      }
    }
    func fonts(_ name: String) -> [String: String] {
      guard let group = value.descendants(0, named: name, namespaces: Self.a).first else { return [:] }
      var result: [String: String] = [:]
      for index in value.nodes[group].children where Self.a.contains(value.nodes[index].namespace) {
        let node = value.nodes[index]
        if let face = node.attributes["typeface"], !face.isEmpty { result[node.attributes["script"] ?? node.name] = String(face.prefix(200)) }
      }
      return result
    }
    return .init(part: part, colors: colors, headingFonts: fonts("majorFont"), bodyFonts: fonts("minorFont"))
  }

  private func shapes(_ value: OfficeXMLDocument, inherited: [CompanyPresentationProfile.Placeholder], part: String)
    -> (placeholders: [CompanyPresentationProfile.Placeholder], decorations: [CompanyPresentationProfile.Decoration], notices: [String]) {
    var placeholders: [CompanyPresentationProfile.Placeholder] = [], decorations: [CompanyPresentationProfile.Decoration] = [], notices: [String] = []
    guard let common = value.children(0, named: "cSld", namespaces: Self.p).first,
          let tree = value.children(common, named: "spTree", namespaces: Self.p).first else { return ([], [], ["図形構造を計測できませんでした。"]) }
    for index in value.nodes[tree].children where Self.p.contains(value.nodes[index].namespace) {
      let node = value.nodes[index]
      guard ["sp", "pic", "cxnSp", "graphicFrame", "grpSp"].contains(node.name) else { continue }
      let frame = node.name == "grpSp" ? nil : frame(value, parent: index)
      let id = value.descendants(index, named: "cNvPr", namespaces: Self.p).first.flatMap { value.nodes[$0].attributes["id"] } ?? String(index)
      if let ph = value.descendants(index, named: "ph", namespaces: Self.p).first {
        let attrs = value.nodes[ph].attributes
        let kind = attrs["type"] ?? "obj", number = attrs["idx"] ?? "0"
        let candidates = inherited.filter { $0.kind == kind || ["title", "ctrTitle"].contains(kind) && ["title", "ctrTitle"].contains($0.kind) }
        let parent = candidates.first { $0.index == number } ?? (["title", "ctrTitle"].contains(kind) && candidates.count == 1 ? candidates.first : nil)
        placeholders.append(.init(index: number, kind: kind, frame: frame ?? parent?.frame,
          frameSource: frame == nil ? parent?.frameSource : part, font: explicitFont(value, parent: index) ?? parent?.font,
          fontSize: fontSize(value, parent: index) ?? parent?.fontSize))
      } else { decorations.append(.init(id: id, kind: node.name, frame: frame)) }
      if node.name == "grpSp" { notices.append("グループ図形の変換後の位置は未計測です。") }
      if let transform = value.descendants(index, named: "xfrm", namespaces: Self.a).first,
         value.nodes[transform].attributes.keys.contains(where: { ["rot", "flipH", "flipV"].contains($0) }) {
        notices.append("回転・反転を持つ図形があります。位置は変換前の値です。")
      }
    }
    return (placeholders, decorations, Array(Set(notices)).sorted())
  }

  private func frame(_ value: OfficeXMLDocument, parent: Int) -> CompanyPresentationProfile.Frame? {
    let transforms = value.descendants(parent, named: "xfrm", namespaces: Self.a.union(Self.p))
    guard let transform = transforms.first,
          let off = value.children(transform, named: "off", namespaces: Self.a).first,
          let ext = value.children(transform, named: "ext", namespaces: Self.a).first,
          let x = value.nodes[off].attributes["x"].flatMap(Int.init), abs(Double(x)) <= 1_000_000_000,
          let y = value.nodes[off].attributes["y"].flatMap(Int.init), abs(Double(y)) <= 1_000_000_000,
          let w = positive(value.nodes[ext].attributes["cx"]), let h = positive(value.nodes[ext].attributes["cy"]) else { return nil }
    return .init(x: x, y: y, width: w, height: h)
  }

  private func fontSize(_ value: OfficeXMLDocument, parent: Int) -> Double? {
    for name in ["defRPr", "rPr", "endParaRPr"] {
      if let size = value.descendants(parent, named: name, namespaces: Self.a).first.flatMap({ value.nodes[$0].attributes["sz"] }).flatMap(Double.init), size.isFinite, (100...40000).contains(size) { return size / 100 }
    }
    return nil
  }

  private func explicitFont(_ value: OfficeXMLDocument, parent: Int) -> String? {
    for name in ["ea", "latin"] {
      if let face = value.descendants(parent, named: name, namespaces: Self.a).first.flatMap({ value.nodes[$0].attributes["typeface"] }), !face.isEmpty { return String(face.prefix(200)) }
    }
    return nil
  }

  private func background(_ value: OfficeXMLDocument) -> String? {
    guard let common = value.children(0, named: "cSld", namespaces: Self.p).first,
          let bg = value.children(common, named: "bg", namespaces: Self.p).first else { return nil }
    if ["gradFill", "blipFill", "pattFill"].contains(where: { !value.descendants(bg, named: $0, namespaces: Self.a).isEmpty }) {
      return "画像・グラデーション等（再現未検証）"
    }
    for name in ["srgbClr", "schemeClr", "sysClr"] {
      if let index = value.descendants(bg, named: name, namespaces: Self.a).first {
        let transforms = value.nodes[index].children.isEmpty ? "" : "（明暗・透明度等の変換あり）"
        return name + ": " + (value.nodes[index].attributes["val"] ?? "未指定") + transforms
      }
    }
    return "画像・グラデーション等（再現未検証）"
  }
}

private extension Array {
  var only: Element? { count == 1 ? first : nil }
}
