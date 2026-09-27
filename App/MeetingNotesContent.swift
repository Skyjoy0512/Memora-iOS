import SwiftUI
import PhotosUI
import UIKit

struct MeetingNotesContent: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var photoItem: PhotosPickerItem?
  @State private var editingPhoto: PhotoEditRequest?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var photoImages: [String: UIImage] = [:]

  var body: some View {
    let photos = model.meeting(id: meetingID)?.photoFileNames ?? []
    let noteText = model.meeting(id: meetingID)?.notes ?? ""

    VStack(alignment: .leading, spacing: 14) {
      Text("ノート")
        .font(.title2.bold())
        .memoraTextReveal()

      InlineMarkdownEditor(
        text: noteText,
        placeholder: "タップして入力",
        minHeight: 360,
        draftKey: "meeting.\(meetingID).notes",
        onCommit: { await model.updateMeetingNotes(meetingID, notes: $0) }
      )

      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(Array(photos.enumerated()), id: \.offset) { index, name in
            if let image = photoImages[name] {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                  Button {
                    model.removeMeetingPhoto(meetingID, index: index)
                  } label: {
                    Image(icon: .xmark)
                      .font(.footnote.weight(.bold))
                      .foregroundStyle(.white)
                      .frame(width: 26, height: 26)
                      .background(.black.opacity(0.45), in: Circle())
                      .padding(6)
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("写真を削除")
                }
            }
          }

          PhotosPicker(selection: $photoItem, matching: .images) {
            VStack(spacing: 8) {
              Image(icon: .photoBadgePlus)
                .font(.title2)
              Text("写真を追加")
                .font(.caption.weight(.medium))
            }
            .foregroundStyle(.primary)
            .frame(width: 160, height: 160)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("写真を追加")
        }
      }
      .scrollIndicators(.hidden)
    }
    .memoraAppear()
    .animation(reduceMotion ? nil : .smooth, value: photos.count)
    .onChange(of: photoItem) { _, item in
      Task { await addPhoto(item) }
    }
    .task(id: photos) {
      for name in photos where photoImages[name] == nil {
        photoImages[name] = await MediaImageCache.image(named: name, maxPixelSize: 480)
      }
    }
    .sheet(item: $editingPhoto) { request in
      PhotoEditorView(source: request.data) { edited in
        // The full-size photo is what gets stored; lists pay for a small copy.
        guard let original = ImageDownscale.jpeg(edited, maxSide: 1024, quality: 0.85) else { return }
        model.addMeetingPhoto(meetingID, data: original)
      }
    }
  }

  private func addPhoto(_ item: PhotosPickerItem?) async {
    guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
    photoItem = nil
    editingPhoto = PhotoEditRequest(data: data)
  }
}
