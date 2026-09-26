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
  @State private var locationCapture = LocationCaptureService()

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("種類", selection: $kind) {
            ForEach(LifeLogKind.allCases) { item in
              Label(item.label, icon: item.symbol).tag(item)
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

            Button {
              locationCapture.requestCurrentPlace()
            } label: {
              switch locationCapture.state {
              case .locating:
                HStack(spacing: 10) {
                  ProgressView()
                  Text("現在地を確認中")
                }
              default:
                Label("現在地から場所を取得", icon: .locationFill)
              }
            }
            .disabled(locationCapture.state == .locating)
          } header: {
            Text("場所")
          } footer: {
            switch locationCapture.state {
            case .found(let name):
              Text("「\(name)」を候補にしました。必要なら編集できます。")
            case .failed(let message):
              Text(message)
            default:
              Text("近くの駅を候補にします。取得した場所名は保存前に編集できます。")
            }
          }
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
          guard let data = try? await newValue?.loadTransferable(type: Data.self) else { return }
          photoItem = nil
          editingPhoto = PhotoEditRequest(data: data)
        }
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
      .onChange(of: locationCapture.state) { _, newState in
        if case .found(let name) = newState {
          locationName = name
          if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = "\(name)に到着"
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
