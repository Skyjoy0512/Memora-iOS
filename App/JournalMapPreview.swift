import MapKit
import SwiftUI

struct JournalMapPreview: View {
  @Environment(\.colorScheme) private var colorScheme
  var place: JournalPlace
  var date: Date?
  @State private var image: UIImage?
  @State private var failed = false
  @State private var retry = 0
  @State private var isExpanded = false

  private var cacheKey: String {
    "\(place.latitude),\(place.longitude),\(colorScheme == .dark),\(retry)"
  }

  var body: some View {
    Button {
      if failed { retry += 1 } else { isExpanded = true }
    } label: {
      ZStack {
        Color(uiColor: .secondarySystemBackground)
        if let image {
          Image(uiImage: image).resizable().scaledToFit()
        } else if failed {
          Text("地図を読み込めませんでした。タップして再試行")
            .font(.caption).padding()
        } else {
          ProgressView().accessibilityLabel("地図を読み込み中")
        }
        if !failed {
          VStack {
          Spacer()
          Label("地図を拡大", icon: .locationFill)
            .font(.caption.weight(.semibold))
            .padding(8).background(.regularMaterial, in: Capsule())
            .padding(8)
          }
        }
      }
      .frame(maxWidth: .infinity).frame(height: 140)
      .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(failed ? "\(place.name)の地図を再読み込み" : "\(place.name)の地図を拡大")
    .sheet(isPresented: $isExpanded) { JournalMapSheet(place: place, date: date) }
    .task(id: cacheKey) {
      image = nil
      failed = false
      if let cached = Self.cache.object(forKey: cacheKey as NSString) {
        image = cached
        return
      }
      let options = MKMapSnapshotter.Options()
      options.region = MKCoordinateRegion(center: place.coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.012))
      options.size = CGSize(width: 600, height: 280)
      options.scale = 1
      options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
      let snapshotter = MKMapSnapshotter(options: options)
      do {
        let snapshot = try await withTaskCancellationHandler {
          try await snapshotter.start()
        } onCancel: {
          snapshotter.cancel()
        }
        try Task.checkCancellation()
        let renderer = UIGraphicsImageRenderer(size: options.size)
        let rendered = renderer.image { context in
          snapshot.image.draw(at: .zero)
          let point = snapshot.point(for: place.coordinate)
          UIColor.systemRed.setFill()
          context.cgContext.fillEllipse(in: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
          UIColor.white.setStroke()
          context.cgContext.setLineWidth(2)
          context.cgContext.strokeEllipse(in: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
        }
        Self.cache.setObject(rendered, forKey: cacheKey as NSString)
        image = rendered
      } catch {
        guard !Task.isCancelled else { return }
        failed = true
      }
    }
  }

  private static let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 40
    return cache
  }()
}
