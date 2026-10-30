import SwiftUI

struct EditorDraftField {
  var name: String
  var value: String
  var restore: (String) -> Void

  init<Value: Codable>(_ name: String, _ binding: Binding<Value>) {
    self.name = name
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    value = (try? encoder.encode(binding.wrappedValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    restore = { text in
      guard let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(Value.self, from: data) else { return }
      binding.wrappedValue = value
    }
  }
}

func optionalDate(_ binding: Binding<Date>, enabled: Bool) -> Binding<Date?> {
  Binding(get: { enabled ? binding.wrappedValue : nil }, set: { if let date = $0 { binding.wrappedValue = date } })
}
