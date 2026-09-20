import SwiftUI
import PhotosUI
import UIKit

struct MeetingNotesContent: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var photoItem: PhotosPickerItem?

  var body: some View {
    let photos = model.meeting(id: meetingID)?.photoData ?? []
    let noteText = model.meeting(id: meetingID)?.notes ?? ""

    VStack(alignment: .leading, spacing: 14) {
      Text("ノート")
        .font(.title2.bold())
        .memoraTextReveal()

      InlineMarkdownEditor(
        text: noteText,
        placeholder: "タップして入力",
        minHeight: 360,
        onCommit: { model.updateMeetingNotes(meetingID, notes: $0) }
      )

      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
            if let image = UIImage(data: data) {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                  Button {
                    model.removeMeetingPhoto(meetingID, index: index)
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                      .font(.title3)
                      .symbolRenderingMode(.palette)
                      .foregroundStyle(.white, .black.opacity(0.45))
                      .padding(6)
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("写真を削除")
                }
            }
          }

          PhotosPicker(selection: $photoItem, matching: .images) {
            VStack(spacing: 8) {
              Image(systemName: "photo.badge.plus")
                .font(.title2)
              Text("写真を追加")
                .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
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
    .animation(.smooth, value: photos.count)
    .onChange(of: photoItem) { _, item in
      Task { await addPhoto(item) }
    }
  }

  private func addPhoto(_ item: PhotosPickerItem?) async {
    guard let item,
          let data = try? await item.loadTransferable(type: Data.self),
          let small = ImageDownscale.jpeg(data) else { return }
    model.addMeetingPhoto(meetingID, data: small)
    photoItem = nil
  }
}
