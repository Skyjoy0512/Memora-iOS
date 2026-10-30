import MapKit
import SwiftUI

struct JournalMapSheet: View {
  @Environment(\.dismiss) private var dismiss
  var place: JournalPlace
  var date: Date?

  var body: some View {
    NavigationStack {
      Map(initialPosition: .region(MKCoordinateRegion(
        center: place.coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
      ))) {
        Marker(place.name, coordinate: place.coordinate)
      }
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 8) {
          Text(place.name).font(.headline)
          if let date {
            Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP"))))
              .font(.subheadline).foregroundStyle(.secondary)
          }
          Button("Appleマップで開く") {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
            item.name = place.name
            item.openInMaps()
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding().background(.regularMaterial)
      }
      .navigationTitle("場所")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
    }
  }
}
