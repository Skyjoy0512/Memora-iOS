import PhotosUI
import SwiftUI

struct LifeLogCreationSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var kind = LifeLogKind.memo
  @State private var title = ""
  @State private var detail = ""
  @State private var createdAt = Date.now
  @State private var eventDate = Date.now.addingTimeInterval(3_600)
  @State private var locationName = ""
  @State private var photoItem: PhotosPickerItem?
  @State private var photoData: Data?
  @State private var editingPhoto: PhotoEditRequest?
  @State private var place: JournalPlace?
  @State private var personIDs: Set<UUID> = []
  @State private var saveError = false

  init(date: Date = .now) {
    _createdAt = State(initialValue: date)
    _eventDate = State(initialValue: date.addingTimeInterval(3_600))
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          MemoraSectionPicker(items: LifeLogKind.allCases, selection: $kind, title: \.label)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
        }

        Section("内容") {
          TextField(titlePrompt, text: $title)
          TextField("ひとことや背景", text: $detail, axis: .vertical)
            .lineLimit(3...6)
          DatePicker("記録した時刻", selection: $createdAt)
        }

        if kind == .event {
          Section("イベント") {
            DatePicker("開始", selection: $eventDate)
          }
        }

        if kind == .location || kind == .event {
          JournalPlaceField(name: $locationName, place: $place)
        }
        if kind != .location {
          JournalPeopleFields(people: model.people, selection: $personIDs)
        }

        Section("写真") {
          PhotosPicker(selection: $photoItem, matching: .images) {
            Label(photoData == nil ? "写真を選択" : "写真を変更", icon: .photoBadgePlus)
          }

          if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(maxWidth: .infinity)
              .frame(height: 190)
              .clipShape(RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
          }
        }
      }
      .navigationTitle("ライフログを追加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("追加", icon: .plus, action: save)
            .disabled(!canSave)
        }
      }
      .onChange(of: photoItem) { _, newValue in
        Task {
          guard let data = try? await newValue?.loadTransferable(type: Data.self) else { return }
          photoItem = nil
          editingPhoto = PhotoEditRequest(data: data)
        }
      }
      .alert("保存できませんでした", isPresented: $saveError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("人物の登録状態や保存領域を確認して、もう一度お試しください。入力内容はこの画面に残っています。")
      }
      .sheet(item: $editingPhoto) { request in
        PhotoEditorView(source: request.data) { edited in
          // Keep the full-size photo; the model stores a small copy for lists.
          guard let original = ImageDownscale.jpeg(edited, maxSide: 2048, quality: 0.85) else { return }
          photoData = original
          if kind == .memo {
            kind = .photo
          }
        }
      }
    }
    .presentationDetents([.large])
  }

  private var titlePrompt: String {
    switch kind {
    case .memo: "メモのタイトル"
    case .photo: "写真のタイトル"
    case .event: "イベント名"
    case .location: "例：駅に到着"
    }
  }

  private var canSave: Bool {
    let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return switch kind {
    case .memo, .event: hasTitle
    case .photo: hasTitle || photoData != nil
    case .location: hasTitle || !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private func save() {
    guard canSave else { return }
    let includesPlace = kind == .location || kind == .event
    let saved = model.addLifeLogEntry(
      kind: kind,
      title: title,
      summary: detail,
      createdAt: createdAt,
      photoData: photoData,
      eventDate: kind == .event ? eventDate : nil,
      locationName: includesPlace ? locationName : nil,
      place: includesPlace ? place : nil,
      personIDs: kind == .location ? [] : personIDs
    )
    if saved { dismiss() } else { saveError = true }
  }
}
