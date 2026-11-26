import SwiftUI

struct ProjectPhotoViewer: View {
  var photo: ProjectPhoto
  @Environment(\.dismiss) private var dismiss
  @State private var state = LoadState.loading

  private enum LoadState {
    case loading
    case loaded(UIImage)
    case unavailable
  }

  var body: some View {
    NavigationStack {
      Group {
        switch state {
        case .loading:
          ProgressView()
        case .loaded(let image):
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("\(photo.recordTitle)の写真")
        case .unavailable:
          ContentUnavailableView("写真を表示できません", icon: .photo)
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
    .task(id: photo) {
      state = .loading
      let image = await MediaImageCache.photo(named: photo.name, maxPixelSize: 2_048)
      guard !Task.isCancelled else { return }
      state = image.map(LoadState.loaded) ?? .unavailable
    }
  }
}
