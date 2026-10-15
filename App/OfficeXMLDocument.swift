import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A small bounded tree, used only on the extraction worker. Entities and DTDs
/// are refused before XMLParser sees them; relationships are package paths only.
final class OfficeXMLDocument: NSObject, XMLParserDelegate {
  private(set) var nodes: [Node] = []
  private var stack: [Int] = []
  private var failure: OfficeArchiveReader.Failure?
  private var textBytes = 0

  struct Node {
    var name: String
    var namespace: String
    var attributes: [String: String]
    var text = ""
    var children: [Int] = []

    var relationshipID: String? {
      let matches = attributes.filter { $0.key.contains(":") && $0.key.split(separator: ":").last == "id" }
      return matches.count == 1 ? matches.first?.value : nil
    }
  }

  init(data: Data) throws {
    super.init()
    guard data.count <= OfficeArchiveReader.maximumPartBytes else { throw OfficeArchiveReader.Failure.limit }
    guard let text = String(data: data, encoding: .utf8), !text.contains("\0"),
          text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
          text.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { throw OfficeArchiveReader.Failure.unsupported }
    try Task.checkCancellation()
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities = false
    parser.externalEntityResolvingPolicy = .never
    parser.delegate = self
    let success = parser.parse()
    try Task.checkCancellation()
    if let failure { throw failure }
    guard success, !nodes.isEmpty, stack.isEmpty else { throw OfficeArchiveReader.Failure.invalid }
  }

  func matches(_ index: Int, _ name: String, namespaces: Set<String>) -> Bool {
    nodes[index].name == name && namespaces.contains(nodes[index].namespace)
  }

  func children(_ parent: Int, named name: String, namespaces: Set<String>) -> [Int] {
    nodes[parent].children.filter { matches($0, name, namespaces: namespaces) }
  }

  func descendants(_ parent: Int, named name: String, namespaces: Set<String>) -> [Int] {
    var found: [Int] = []
    func visit(_ index: Int) {
      guard !["del", "moveFrom"].contains(nodes[index].name) else { return }
      if matches(index, name, namespaces: namespaces) { found.append(index); return }
      for child in nodes[index].children { visit(child) }
    }
    visit(parent)
    return found
  }

  func text(_ parent: Int, namespaces: Set<String>) -> String {
    var output = ""
    func visit(_ index: Int) {
      let node = nodes[index]
      guard !["del", "moveFrom", "rPh"].contains(node.name) else { return }
      if namespaces.contains(node.namespace) {
        if node.name == "t" { output += node.text }
        if node.name == "tab" { output += "\t" }
        if node.name == "br" || node.name == "cr" { output += "\n" }
      }
      for child in node.children { visit(child) }
    }
    visit(parent)
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
              qualifiedName: String?, attributes attributeDict: [String: String]) {
    guard !Task.isCancelled, stack.count < 48, nodes.count < 30_000 else {
      failure = .limit; parser.abortParsing(); return
    }
    let index = nodes.count
    nodes.append(Node(name: elementName, namespace: namespaceURI ?? "", attributes: attributeDict))
    if let parent = stack.last { nodes[parent].children.append(index) }
    stack.append(index)
  }

  func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) {
    if !stack.isEmpty { stack.removeLast() }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    textBytes += string.utf8.count
    guard !Task.isCancelled, textBytes <= OfficeArchiveReader.maximumPartBytes else {
      failure = .limit; parser.abortParsing(); return
    }
    if let current = stack.last { nodes[current].text += string }
  }

  func parser(_ parser: XMLParser, foundCDATA data: Data) {
    guard let text = String(data: data, encoding: .utf8) else {
      failure = .invalid; parser.abortParsing(); return
    }
    self.parser(parser, foundCharacters: text)
  }

  func parser(_ parser: XMLParser, resolveExternalEntityName: String, systemID: String?) -> Data? { nil }
}
