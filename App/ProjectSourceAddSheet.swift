import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ProjectSourceAddSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var projectID: UUID
  @State private var link = ""
  @State private var noteTitle = ""
  @State private var noteText = ""
  @State private var photos: [PhotosPickerItem] = []
  @State private var isImportingFiles = false
  @State private var isMovingRecords = false
  @State private var isSaving = false
  @State private var message: String?
  @State private var failed = false
  @FocusState private var focusedField: Field?
  private enum Field: Hashable { case link, title, body }

  var body: some View {
    NavigationStack {
      ScrollViewReader { scroll in
      Form {
        if let message {
          Section {
            Text(message).font(.subheadline)
              .foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
              .accessibilityLabel(message)
          }
        }
        Section("リンク") {
          TextField("YouTube・WebのURL", text: $link)
            .focused($focusedField, equals: .link)
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
          Button("リンクを保存", icon: .link) {
            perform {
              guard let id = try model.addProjectLink(link, projectID: projectID) else { return false }
              link = ""
              return model.source(id: id) != nil
            }
          }.disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        Section {
          PhotosPicker(selection: $photos, maxSelectionCount: 6, matching: .images) {
            Label("写真を選択", icon: .photo)
          }
          Button("ファイルを選択", icon: .doc) { isImportingFiles = true }
          Button("既存記録を移動", icon: .folder) { isMovingRecords = true }
        } footer: {
          Text("ファイルは50MBまで。録音・音声取り込みは右下の＋からも始められます。")
        }
        Section("テキストメモ") {
          TextField("タイトル", text: $noteTitle)
            .focused($focusedField, equals: .title)
          TextEditor(text: $noteText).frame(minHeight: 120).accessibilityLabel("メモ本文")
            .focused($focusedField, equals: .body)
            .id(Field.body)
          Button("メモを保存", icon: .noteText) {
            perform {
              guard try await model.addProjectNote(title: noteTitle, text: noteText, projectID: projectID) != nil else { return false }
              DraftStore.clear("workspace.newNote.\(projectID)")
              noteTitle = ""; noteText = ""
              return true
            }
          }.disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: focusedField) { _, field in
        if field == .body { scroll.scrollTo(Field.body, anchor: .center) }
      }
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
        // The keyboard resizes the form after focus changes. Follow that layout
        // change once, so the native editor stays above it without a timer.
        if focusedField == .body { scroll.scrollTo(Field.body, anchor: .center) }
      }
      }
      .disabled(isSaving || model.isRestoring || model.space(id: projectID) == nil)
      .onAppear { noteText = DraftStore.load("workspace.newNote.\(projectID)") ?? "" }
      .onChange(of: noteText) { _, value in
        if value.isEmpty { DraftStore.clear("workspace.newNote.\(projectID)") }
        else { DraftStore.save(value, key: "workspace.newNote.\(projectID)") }
      }
      .navigationTitle("ソースを追加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("キーボードを閉じる", icon: .chevronDown) { focusedField = nil }
            .labelStyle(.iconOnly)
        }
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
      .fileImporter(isPresented: $isImportingFiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
        switch result {
        case .success(let urls):
          perform {
            var count = 0
            for url in urls.prefix(10) {
              if try await model.importProjectFile(url, projectID: projectID) != nil { count += 1 }
            }
            if count > 0 { message = "\(count)件を保存しました。" }
            return count > 0
          }
        case .failure(let error): message = error.localizedDescription; failed = true
        }
      }
      .onChange(of: photos) { _, items in
        guard !items.isEmpty else { return }
        perform {
          var count = 0
          for item in items {
            if let photo = try await item.loadTransferable(type: ProjectPhotoTransfer.self),
               await model.addProjectFile(receipt: photo.receipt, title: "写真", projectID: projectID) != nil { count += 1 }
          }
          photos = []
          if count > 0 { message = "\(count)件を保存しました。" }
          return count > 0
        }
      }
      .sheet(isPresented: $isMovingRecords) { ProjectFilePickerSheet(spaceID: projectID) }
      .tint(MemoraPalette.textPrimary)
    }
  }

  private func perform(_ operation: @escaping @MainActor () async throws -> Bool) {
    guard !isSaving else { return }
    isSaving = true; message = nil; failed = false
    Task { @MainActor in
      defer { isSaving = false }
      do {
        if try await operation() { message = message ?? "保存しました。" }
        else { message = model.persistenceFailureMessage ?? "保存できませんでした。"; failed = true }
      } catch { message = error.localizedDescription; failed = true }
    }
  }
}
