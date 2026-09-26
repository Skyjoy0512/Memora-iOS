import SwiftUI
import UIKit

/// One journal entry in full: its photo, text, and where it came from, with
/// editing and deleting.
struct LifeLogEntryDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var entryID: UUID
  @State private var isEditing = false
  @State private var isDeleting = false
  @State private var isViewingPhoto = false

  var body: some View {
    NavigationStack {
      Group {
        if let entry = currentEntry {
          content(entry)
        } else {
          ContentUnavailableView("記録が見つかりません", systemImage: "doc.questionmark")
        }
      }
      .navigationTitle("記録")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu("その他", systemImage: "ellipsis") {
            Button("編集", systemImage: "pencil") { isEditing = true }
            if let entry = currentEntry, let latitude = entry.latitude, let longitude = entry.longitude {
              Button("この場所を今後記録しない", systemImage: "mappin.slash") {
                AutoLocationLogger.addExcludedPlace(
                  name: entry.title,
                  latitude: latitude,
                  longitude: longitude
                )
              }
            }
            Button("削除", systemImage: "trash", role: .destructive) { isDeleting = true }
          }
        }
      }
      .sheet(isPresented: $isEditing) {
        if let entry = currentEntry {
          LifeLogEditSheet(entry: entry)
        }
      }
      .fullScreenCover(isPresented: $isViewingPhoto) {
        if let image = photo {
          LifeLogPhotoViewer(image: image)
        }
      }
      .confirmationDialog("この記録を削除しますか？", isPresented: $isDeleting, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          model.deleteLifeLogEntry(entryID)
          dismiss()
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("「最近削除した項目」に移動します。30日間は元に戻せます。")
      }
      .task(id: currentEntry?.photoFileName) {
        await loadPhoto()
      }
    }
  }

  private var currentEntry: LifeLogEntry? {
    model.lifeLogEntries.first { $0.id == entryID }
  }

  @State private var photo: UIImage?

  /// Reads the photo at the size it is shown, off the main thread.
  private func loadPhoto() async {
    guard let name = currentEntry?.photoFileName else {
      photo = nil
      return
    }
    let loaded = await MediaImageCache.photo(named: name)
    guard !Task.isCancelled, currentEntry?.photoFileName == name else { return }
    photo = loaded
  }

  private func content(_ entry: LifeLogEntry) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 8) {
          Image(systemName: entry.kind.symbol)
          Text(entry.kind.label)
          Text("·")
          Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)

        if let image = photo {
          Button {
            isViewingPhoto = true
          } label: {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(maxWidth: .infinity)
              .frame(height: 260)
              .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("写真を拡大")
        }

        Text(entry.title)
          .font(.title2.bold())

        if !entry.summary.isEmpty {
          Text(entry.summary)
            .font(.body)
            .lineSpacing(4)
        }

        if let locationName = entry.locationName, !locationName.isEmpty {
          Label(locationName, systemImage: "location.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
    }
    .background(Color(uiColor: .systemBackground))
  }
}

/// A photo at full size, pinch to zoom.
private struct LifeLogPhotoViewer: View {
  @Environment(\.dismiss) private var dismiss
  var image: UIImage
  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .scaleEffect(scale)
        .gesture(
          MagnifyGesture()
            .onChanged { value in
              let delta = value.magnification / (lastScale == 0 ? 1 : lastScale)
              lastScale = value.magnification
              scale = min(max(1, scale * delta), 6)
            }
            .onEnded { _ in
              lastScale = 1
            }
        )

      VStack {
        HStack {
          Spacer()
          Button("写真を閉じる", systemImage: "xmark") {
            dismiss()
          }
          .labelStyle(.iconOnly)
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(.white.opacity(0.12), in: Circle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)

        Spacer()
      }
    }
  }
}
