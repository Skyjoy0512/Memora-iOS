import SwiftUI

/// Places the automatic logger never records: home, the office, anywhere the
/// person does not want a line. Each is stored as a name and a rounded point.
struct ExcludedPlacesView: View {
  @State private var places: [AutoLocationLogger.ExcludedPlace] = []

  var body: some View {
    List {
      if places.isEmpty {
        ContentUnavailableView {
          Label("記録しない場所はありません", systemImage: "mappin.slash")
        } description: {
          Text("記録の詳細から「この場所を今後記録しない」を選ぶと、ここに並びます。")
        }
        .listRowBackground(Color.clear)
      } else {
        ForEach(places) { place in
          Label(place.name, systemImage: "mappin.slash")
            .accessibilityLabel("記録しない場所、\(place.name)")
        }
        .onDelete(perform: delete)
      }
    }
    .navigationTitle("記録しない場所")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { places = AutoLocationLogger.excludedPlaces }
  }

  private func delete(at offsets: IndexSet) {
    for index in offsets {
      AutoLocationLogger.removeExcludedPlace(places[index].id)
    }
    places = AutoLocationLogger.excludedPlaces
  }
}
