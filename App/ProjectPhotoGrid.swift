import SwiftUI

/// The project's photos as thumbnails, opened at full size. The record keeps the
/// file; this only reads it.
struct ProjectPhotoGrid: View {
  var photos: [ProjectPhoto]
  @State private var images: [String: UIImage] = [:]
  @State private var viewing: ProjectPhoto?

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: MemoraSpacing.sm)],
              spacing: MemoraSpacing.sm) {
      ForEach(photos) { photo in
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
    .task(id: photos) {
      for photo in photos where images[photo.id] == nil {
        images[photo.id] = await MediaImageCache.image(named: photo.name, maxPixelSize: 320)
      }
    }
    .sheet(item: $viewing) { photo in
      ProjectPhotoViewer(photo: photo)
    }
  }
}

private struct ProjectPhotoViewer: View {
  var photo: ProjectPhoto
  @Environment(\.dismiss) private var dismiss
  @State private var image: UIImage?

  var body: some View {
    NavigationStack {
      Group {
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
        } else {
          ProgressView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(MemoraPalette.background)
      .navigationTitle(photo.recordTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
    }
    .task(id: photo.id) {
      image = await MediaImageCache.image(named: photo.name, maxPixelSize: 2_048)
    }
  }
}
