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

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("種類", selection: $kind) {
            ForEach(LifeLogKind.allCases) { item in
              Label(item.label, systemImage: item.symbol).tag(item)
            }
          }
          .pickerStyle(.segmented)
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

        if kind == .location {
          Section {
            TextField("例：渋谷駅", text: $locationName)
          } header: {
            Text("場所")
          } footer: {
            Text("現在地は取得せず、入力した場所だけを保存します。")
          }
        }

        Section("写真") {
          PhotosPicker(selection: $photoItem, matching: .images) {
            Label(photoData == nil ? "写真を選択" : "写真を変更", systemImage: "photo.badge.plus")
          }

          if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(maxWidth: .infinity)
              .frame(height: 190)
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          }
        }
      }
      .navigationTitle("ライフログを追加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("追加", action: save)
            .disabled(!canSave)
        }
      }
      .onChange(of: photoItem) { _, newValue in
        Task {
          photoData = try? await newValue?.loadTransferable(type: Data.self)
          if photoData != nil, kind == .memo {
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
    model.addLifeLogEntry(
      kind: kind,
      title: title,
      summary: detail,
      createdAt: createdAt,
      photoData: photoData,
      eventDate: kind == .event ? eventDate : nil,
      locationName: kind == .location ? locationName : nil
    )
    dismiss()
  }
}
