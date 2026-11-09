import SwiftUI

struct EditorDraftProtection: ViewModifier {
  @Environment(\.dismiss) private var dismiss
  var key: String
  var fields: [EditorDraftField]
  var ready: Bool
  @Binding var cancels: Bool
  var completed: Bool
  @State private var baseline: [String: String]?
  @State private var loadedKey: String?
  @State private var confirmsDiscard = false
  @State private var draftError = false
  @Environment(MemoraModel.self) private var model

  private var values: [String: String] { Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) }) }
  private var isDirty: Bool { baseline.map { $0 != values } ?? false }

  func body(content: Content) -> some View {
    content
      .interactiveDismissDisabled(isDirty)
      .onAppear { prepare() }
      .onDisappear { if completed, let loadedKey { DraftStore.clear(loadedKey) } }
      .onChange(of: ready) { _, _ in prepare() }
      .onChange(of: values) { _, value in
        guard let baseline, loadedKey == key, !completed else { return }
        if value == baseline { DraftStore.clear(key); return }
        do {
          let data = try JSONEncoder().encode(EditorDraftEnvelope(baseline: baseline, values: value))
          try DraftStore.saveAndWait(String(decoding: data, as: UTF8.self), key: key)
        } catch { draftError = true }
      }
      .onChange(of: completed) { _, done in if done, let loadedKey { DraftStore.clear(loadedKey) } }
      .onChange(of: key) { _, _ in dismiss() }
      .onChange(of: cancels) { _, requested in
        guard requested else { return }
        cancels = false
        if isDirty { confirmsDiscard = true } else { dismiss() }
      }
      .confirmationDialog("変更を破棄しますか？", isPresented: $confirmsDiscard, titleVisibility: .visible) {
        Button("変更を破棄", role: .destructive) {
          if let loadedKey { DraftStore.clear(loadedKey) }
          dismiss()
        }
        Button("編集を続ける", role: .cancel) {}
      }
      .alert("下書きを保存できませんでした", isPresented: $draftError) {
        Button("編集を続ける", role: .cancel) {}
      } message: { Text("入力はこの画面に残っています。閉じる前に保存してください。") }
  }

  private func prepare() {
    guard ready, loadedKey == nil else { return }
    let initial = values
    do {
      let text = try DraftStore.readAll([key])[key]
      let envelope: EditorDraftEnvelope?
      if let text {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(EditorDraftEnvelope.self, from: data) else {
          throw DraftStore.Failure.unreadable
        }
        envelope = decoded
      } else { envelope = nil }
      baseline = initial
      loadedKey = key
      if let restored = envelope?.restored(matching: initial) {
        for field in fields { if let value = restored[field.name] { field.restore(value) } }
      }
    } catch {
      model.persistenceFailureMessage = error.localizedDescription
      dismiss()
    }
  }
}

extension View {
  func protectsEditorDraft(key: String, fields: [EditorDraftField], ready: Bool = true,
                           cancels: Binding<Bool>, completed: Bool) -> some View {
    modifier(EditorDraftProtection(key: key, fields: fields, ready: ready, cancels: cancels, completed: completed))
  }
}
