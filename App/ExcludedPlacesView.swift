import SwiftUI

/// Places the automatic logger never records: home, the office, anywhere the
/// person does not want a line. Each is stored as a name and a rounded point.
struct ExcludedPlacesView: View {
  @State private var places: [AutoLocationLogger.ExcludedPlace] = []
  @State private var message: String?
  @State private var service = LocationCaptureService()

  var body: some View {
    List {
      if let message {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .listRowBackground(Color.clear)
      }

      if places.isEmpty {
        ContentUnavailableView {
          Label("記録しない場所はありません", icon: .mappinSlash)
        } description: {
          Text("記録の詳細から「この場所を今後記録しない」を選ぶと、ここに並びます。")
        }
        .listRowBackground(Color.clear)
      } else {
        ForEach(places) { place in
          Label(place.name, icon: .mappinSlash)
            .accessibilityLabel("記録しない場所、\(place.name)")
        }
        .onDelete(perform: delete)
      }
    }
    .navigationTitle("記録しない場所")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarActionItem {
        ToolbarIconButton("現在地を追加", icon: .locationFill) {
          addCurrentPlace()
        }
        .labelStyle(.iconOnly)
      }
    }
    .onAppear { places = AutoLocationLogger.excludedPlaces }
  }

  /// Adds wherever the person is now, so a place can be excluded before it is
  /// ever recorded.
  private func addCurrentPlace() {
    message = "現在地を確認しています…"
    service.requestCurrentPlace { result in
      switch result {
      case .found(let name, let latitude, let longitude):
        AutoLocationLogger.addExcludedPlace(name: name, latitude: latitude, longitude: longitude)
        places = AutoLocationLogger.excludedPlaces
        message = "「\(name)」を追加しました。"
      case .failed(let reason):
        message = reason
      }
    }
  }

  private func delete(at offsets: IndexSet) {
    for index in offsets {
      AutoLocationLogger.removeExcludedPlace(places[index].id)
    }
    places = AutoLocationLogger.excludedPlaces
  }
}
