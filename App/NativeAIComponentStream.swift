import Foundation

/// Scan only new bytes. Each closed component must validate as part of the
/// original envelope; no repaired JSON, expressions or partial items execute.
struct NativeAIComponentStream {
  enum Format { case native, jsonRender }
  private var format = Format.native
  private var completedElements = 0
  var isComplete: Bool { finished && !failed }
  private var previous = ""
  private var offset = 0
  private var stack: [UInt8] = []
  private var inString = false
  private var escaped = false
  private var failed = false
  private var finished = false
  private var interface: NativeAIInterface?
  private(set) var processedBytes = 0
  private(set) var validations = 0

  mutating func update(_ prefix: String, format: Format = .native) -> NativeAIInterface? {
    guard prefix.utf8.count <= 32 * 1024 else { failed = true; return nil }
    if !prefix.hasPrefix(previous) || self.format != format { self = Self() }
    self.format = format
    previous = prefix
    guard !failed else { return nil }
    let bytes = Array(prefix.utf8)
    while offset < bytes.count {
      let byte = bytes[offset]
      defer { offset += 1; processedBytes += 1 }
      if finished {
        if ![UInt8(9), 10, 13, 32].contains(byte) { failed = true; return nil }
        continue
      }
      if inString {
        if escaped { escaped = false }
        else if byte == 92 { escaped = true }
        else if byte == 34 { inString = false }
        continue
      }
      if byte == 34 { inString = true; continue }
      if byte == 123 || byte == 91 {
        guard stack.count < 16 else { failed = true; return nil }
        stack.append(byte)
      } else if byte == 125 || byte == 93 {
        guard stack.last == (byte == 125 ? 123 : 91) else { failed = true; return nil }
        let elementStack: [UInt8] = format == .native ? [123, 91, 123] : [123, 123, 123]
        if byte == 125, stack == elementStack {
          validations += 1
          let candidate = String(decoding: bytes[...offset], as: UTF8.self) + (format == .native ? "]}" : "}}")
          if format == .native {
            guard let value = NativeAIInterface.decode(candidate),
                  value.components.count == (interface?.components.count ?? 0) + 1 else {
              failed = true; return nil
            }
            interface = value
          } else {
            guard let projection = NativeAIInterface.jsonRenderProjection(candidate, isPartial: true),
                  projection.elementCount == completedElements + 1 else {
              failed = true; return nil
            }
            completedElements = projection.elementCount
            interface = projection.interface
          }
        }
        stack.removeLast()
        if stack.isEmpty {
          validations += 1
          let json = String(decoding: bytes[...offset], as: UTF8.self)
          if format == .native {
            guard let value = NativeAIInterface.decode(json) else { failed = true; return nil }
            interface = value
          } else {
            guard let projection = NativeAIInterface.jsonRenderProjection(json, isPartial: false),
                  projection.elementCount == completedElements else { failed = true; return nil }
            interface = projection.interface
          }
          finished = true
        }
      }
    }
    return interface
  }
}
