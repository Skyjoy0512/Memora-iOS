import Foundation

extension NativeAIInterface {
  /// A restricted json-render catalog projected into the existing native renderer.
  /// The wire format supplies presentation, never tool or record permissions.
  static func jsonRenderProjection(_ json: String, isPartial: Bool) -> (interface: Self, elementCount: Int)? {
    guard json.utf8.count <= 32 * 1024,
          let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          Set(object.keys).isSubset(of: ["root", "elements"]),
          let elements = object["elements"] as? [String: Any],
          (1...41).contains(elements.count) else { return nil }
    func validID(_ id: String) -> Bool { (1...80).contains(id.count) }
    let root = object["root"] as? String
    guard root.map(validID) ?? (isPartial && object["root"] == nil) else { return nil }
    var leaves: [String: Component] = [:]
    var children: [String: [String]] = [:]
    var kinds: [String: Kind] = [:]
    var parents: [String: String] = [:]

    for (key, value) in elements {
      guard validID(key), let element = value as? [String: Any],
            Set(element.keys) == ["type", "props", "children"],
            let type = element["type"] as? String,
            let props = element["props"] as? [String: Any],
            let childIDs = element["children"] as? [String],
            childIDs.allSatisfy(validID), Set(childIDs).count == childIDs.count else { return nil }
      children[key] = childIDs
      for child in childIDs {
        guard child != key, parents.updateValue(key, forKey: child) == nil else { return nil }
      }
      if type == "Stack" {
        guard (root == nil || root == key), props.isEmpty, (1...8).contains(childIDs.count) else { return nil }
      } else if type == "Row" || type == "Column" {
        guard props.isEmpty, (1...4).contains(childIDs.count), let kind = Kind(rawValue: type) else { return nil }
        kinds[key] = kind
      } else {
        guard childIDs.isEmpty, Set(props.keys).isSubset(of: ["title", "columns", "items"]),
              let kind = Kind(rawValue: type), kind != .row, kind != .column else { return nil }
        var component = props
        component["id"] = key
        component["kind"] = type
        guard let data = try? JSONSerialization.data(withJSONObject: ["version": 1, "components": [component]]),
              let json = String(data: data, encoding: .utf8),
              let validated = decode(json)?.components.first else { return nil }
        leaves[key] = validated
      }
    }
    // Validate even branches that have not reached the root yet. Shared children
    // and cycles would otherwise alias SwiftUI identity or expand without bound.
    for key in elements.keys {
      var path: Set<String> = [key]
      var parent = parents[key]
      while let current = parent {
        guard path.insert(current).inserted else { return nil }
        parent = parents[current]
      }
    }
    guard let root else {
      return isPartial ? (Self(version: 1, components: []), elements.count) : nil
    }
    guard parents[root] == nil else { return nil }
    guard elements[root] != nil else {
      return isPartial ? (Self(version: 1, components: []), elements.count) : nil
    }
    var visited: Set<String> = [root]
    func component(_ key: String) -> Component? {
      guard visited.insert(key).inserted else { return nil }
      if let leaf = leaves[key] { return leaf }
      guard let kind = kinds[key], let ids = children[key], ids.allSatisfy({ leaves[$0] != nil }) else { return nil }
      guard ids.allSatisfy({ visited.insert($0).inserted }) else { return nil }
      return Component(id: key, kind: kind, components: ids.compactMap { leaves[$0] })
    }
    let components: [Component]
    if let leaf = leaves[root] {
      components = [leaf]
    } else if let kind = kinds[root], let ids = children[root], ids.allSatisfy({ leaves[$0] != nil }) {
      visited.formUnion(ids)
      components = [Component(id: root, kind: kind, components: ids.compactMap { leaves[$0] })]
    } else if kinds[root] == nil {
      components = (children[root] ?? []).compactMap(component)
    } else {
      components = []
    }
    guard isPartial || (!components.isEmpty && visited == Set(elements.keys)) else { return nil }
    // Completed elements must already respect the catalog's shallow layout.
    for (key, _) in kinds {
      for child in children[key] ?? [] where elements[child] != nil {
        guard leaves[child] != nil else { return nil }
      }
    }
    return (Self(version: 1, components: components), elements.count)
  }

  /// Link Markdown citations without rewriting quotes or escapes inside JSON props.
  static func mapAnswerMarkdown(_ text: String, transform: (String) -> String) -> String {
    guard let fence = interfaceFence(in: text) else { return transform(text) }
    return transform(String(text[..<fence.range.lowerBound])) + text[fence.range.lowerBound...]
  }

  static func interfaceFence(in text: String) -> (range: Range<String.Index>, format: NativeAIComponentStream.Format)? {
    [("```memora-ui", NativeAIComponentStream.Format.native), ("```json-render", .jsonRender)]
      .compactMap { marker, format in text.range(of: marker).map { (range: $0, format: format) } }
      .min { $0.range.lowerBound < $1.range.lowerBound }
  }
}
