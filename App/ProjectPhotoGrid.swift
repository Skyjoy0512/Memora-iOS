import SwiftUI

/// The project's photos as thumbnails, opened at full size, searched by the
/// record they belong to or the words written in them. The record keeps the
/// file; this only reads it, and the text is recognized on this device.
struct ProjectPhotoGrid: View {
  @Environment(MemoraModel.self) private var model
  var photos: [ProjectPhoto]
  @State private var images: [String: UIImage] = [:]
  @State private var viewing: ProjectPhoto?
  @State private var isSearching = false
  @State private var query = ""
  @State private var isReadingText = false
  @State private var searchFieldID = UUID()
  @FocusState private var isFocused: Bool

  var body: some View {
    let entries = model.mediaEntriesByName()
    let hasPendingText = photos.contains { photo in
      guard let entry = entries[photo.name] else { return false }
      return entry.textReadAt == nil
    }
    let matching = photos.filter { photo in
      guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
      return entries[photo.name]?.matches(query)
        ?? photo.recordTitle.localizedStandardContains(query)
    }
    VStack(alignment: .leading, spacing: MemoraSpacing.md) {
      header
      if let state = readingState(hasPendingText: hasPendingText) {
        Text(state)
          .font(MemoraTypography.metadata)
          .foregroundStyle(.secondary)
      }
      if matching.isEmpty {
        Text("一致する写真はありません")
          .font(MemoraTypography.secondary)
          .foregroundStyle(.secondary)
      } else {
        grid(matching)
      }
    }
    .task(id: photos) {
      model.reconcileMediaIndex()
      let names = Set(photos.map(\.name))
      isReadingText = model.mediaIndexEntries.contains { names.contains($0.name) && $0.textReadAt == nil }
      guard isReadingText else { return }
      await model.readPendingMediaText(for: names)
      if !Task.isCancelled { isReadingText = false }
    }
    .onDisappear {
      if model.focusedInlineEditorID == searchFieldID { model.focusedInlineEditorID = nil }
    }
  }

  private func readingState(hasPendingText: Bool) -> String? {
    if isReadingText { return "写真の文字を読み取っています…（端末内で処理します）" }
    guard !query.isEmpty, hasPendingText else { return nil }
    return "まだ読み取っていない写真があります。この画面を開くと続きを読み取ります。"
  }

  private var header: some View {
    VStack(spacing: MemoraSpacing.sm) {
      HStack(spacing: MemoraSpacing.md) {
        Text("\(photos.count)枚")
          .font(MemoraTypography.metadata)
          .foregroundStyle(.secondary)
        Spacer()
        Button("写真を検索", icon: .magnifyingglass) {
          isSearching.toggle()
          if !isSearching { query = ""; isFocused = false }
        }
        .labelStyle(.iconOnly)
        .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
        .accessibilityLabel(isSearching ? "写真の検索を閉じる" : "写真を検索")
      }
      if isSearching {
        HStack {
          TextField("記録名・写真の文字で検索", text: $query)
            .focused($isFocused)
            .submitLabel(.search)
            .accessibilityLabel("記録名・写真の文字で検索")
            .id(searchFieldID)
            .task {
              isFocused = true
              model.focusedInlineEditorID = searchFieldID
            }
          Button("検索を閉じる", icon: .xmark) {
            query = ""; isSearching = false; isFocused = false
          }
          .labelStyle(.iconOnly)
          .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
        }
        .padding(.leading, MemoraSpacing.md)
        .background(MemoraPalette.selection, in: Capsule())
      }
    }
    .buttonStyle(.plain)
    .tint(MemoraPalette.textPrimary)
    .onChange(of: isFocused) { _, focused in
      if focused { model.focusedInlineEditorID = searchFieldID }
      else if model.focusedInlineEditorID == searchFieldID { model.focusedInlineEditorID = nil }
    }
  }

  private func grid(_ items: [ProjectPhoto]) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: MemoraSpacing.sm)],
              spacing: MemoraSpacing.sm) {
      ForEach(items) { photo in
        Button {
          viewing = photo
        } label: {
          Group {
            if let image = images[photo.id] {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
            } else {
              Rectangle()
                .fill(MemoraPalette.selection)
            }
          }
          .frame(height: 104)
          .frame(maxWidth: .infinity)
          .clipped()
          .clipShape(RoundedRectangle(cornerRadius: MemoraRadius.field, style: .continuous))
          .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.field, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(photo.recordTitle)の写真")
      }
    }
    .task(id: items) {
      for photo in items where images[photo.id] == nil {
        images[photo.id] = await MediaImageCache.image(named: photo.name, maxPixelSize: 320)
      }
    }
    .sheet(item: $viewing) { photo in
      ProjectPhotoViewer(photo: photo)
    }
  }
}
