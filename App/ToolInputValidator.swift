import Foundation
import CoreFoundation

enum ToolInputValidator {
  static func accepts(_ value: Any, schema: [String: Any], depth: Int = 0) -> Bool {
    guard depth < 12, schema["$ref"] == nil, schema["pattern"] == nil else { return false }
    let allowedKeys: Set<String> = ["type", "title", "description", "default", "examples", "enum", "properties", "required", "additionalProperties", "items", "minItems", "maxItems", "minLength", "maxLength", "minimum", "maximum", "anyOf", "oneOf", "allOf", "$schema", "$id", "deprecated", "readOnly", "writeOnly"]
    guard schema.keys.allSatisfy({ allowedKeys.contains($0) || $0.hasPrefix("x-") }) else { return false }
    if let choices = schema["enum"] as? [Any] {
      let encoded = try? JSONSerialization.data(withJSONObject: ["v": value], options: .sortedKeys)
      guard choices.contains(where: { (try? JSONSerialization.data(withJSONObject: ["v": $0], options: .sortedKeys)) == encoded }) else { return false }
    }
    for key in ["anyOf", "oneOf"] {
      if let choices = schema[key] as? [[String: Any]] {
        let matches = choices.filter { accepts(value, schema: $0, depth: depth + 1) }.count
        guard key == "oneOf" ? matches == 1 : matches > 0 else { return false }
      }
    }
    if let parts = schema["allOf"] as? [[String: Any]], !parts.allSatisfy({ accepts(value, schema: $0, depth: depth + 1) }) { return false }
    let types = (schema["type"] as? String).map { [$0] } ?? (schema["type"] as? [String]) ?? []
    if !types.isEmpty && !types.contains(where: { matches(value, type: $0) }) { return false }
    if let object = value as? [String: Any] {
      guard object.count <= 128 else { return false }
      let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
      if let required = schema["required"] as? [String], !required.allSatisfy({ object[$0] != nil }) { return false }
      for (key, item) in object {
        if let property = properties[key] { if !accepts(item, schema: property, depth: depth + 1) { return false } }
        else if let additional = schema["additionalProperties"] as? [String: Any] {
          if !accepts(item, schema: additional, depth: depth + 1) { return false }
        } else if schema["additionalProperties"] as? Bool == false { return false }
      }
    }
    if let list = value as? [Any] {
      guard list.count <= 128, list.count >= (schema["minItems"] as? Int ?? 0), list.count <= (schema["maxItems"] as? Int ?? 128) else { return false }
      if let items = schema["items"] as? [String: Any], !list.allSatisfy({ accepts($0, schema: items, depth: depth + 1) }) { return false }
    }
    if let text = value as? String {
      guard text.utf8.count <= 32 * 1024, text.count >= (schema["minLength"] as? Int ?? 0), text.count <= (schema["maxLength"] as? Int ?? 32 * 1024) else { return false }
    }
    if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
      if let minimum = schema["minimum"] as? NSNumber, number.doubleValue < minimum.doubleValue { return false }
      if let maximum = schema["maximum"] as? NSNumber, number.doubleValue > maximum.doubleValue { return false }
    }
    return true
  }
  private static func matches(_ value: Any, type: String) -> Bool {
    switch type {
    case "object": value is [String: Any]
    case "array": value is [Any]
    case "string": value is String
    case "null": value is NSNull
    case "boolean": (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
    case "number": (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite } ?? false
    case "integer": (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && $0.doubleValue.rounded() == $0.doubleValue } ?? false
    default: false
    }
  }
}
