import SwiftUI
import UIKit

struct ProjectSourceThumbnail: View {
  var source: ProjectSource
  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image).resizable().scaledToFill()
          .frame(width: 32, height: 32).clipped()
          .clipShape(RoundedRectangle(cornerRadius: 4))
      } else {
        Image(icon: source.icon, size: 17).foregroundStyle(.secondary)
          .frame(width: 32, height: 32)
      }
    }
    .accessibilityHidden(true)
    .task(id: source.thumbnailReference) {
      image = nil
      guard let name = source.thumbnailReference else { return }
      let decoded = await MediaImageCache.sourceThumbnail(named: name, maxPixelSize: 96)
      guard !Task.isCancelled else { return }
      image = decoded
    }
  }
}
