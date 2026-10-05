import MapKit
import SwiftUI

struct JournalPlacePicker: View {
  @Environment(\.dismiss) private var dismiss
  var onSelect: (JournalPlace) -> Void
  @State private var query = ""
  @State private var results: [MKMapItem] = []
  @State private var selection: JournalPlace?
  @State private var capture = LocationCaptureService()
  @State private var isSearching = false
  @State private var message: String?
  @State private var usedCurrentLocation = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          TextField("施設名・住所を検索", text: $query)
            .submitLabel(.search)
          Button {
            capture.requestCurrentPlace { result in
              if case .found(let name, let latitude, let longitude) = result {
                selection = JournalPlace(name: name, latitude: latitude, longitude: longitude)
                usedCurrentLocation = true
              }
            }
          } label: {
            Label(capture.state == .locating ? "現在地を確認中…" : "現在地を使う", icon: .locationFill)
          }
          .disabled(capture.state == .locating)
          if case .failed(let error) = capture.state {
            Text(error).font(.footnote).foregroundStyle(.secondary)
          }
        }
        if let selection {
          Section("選択した場所") {
            Text(selection.name).font(.headline)
            JournalMapPreview(place: selection)
            if usedCurrentLocation {
              Text("現在地はおおよその位置です。場所名は近くの施設などの候補です。")
                .font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
        Section("検索結果") {
          if isSearching { ProgressView("検索中…") }
          if let message { Text(message).foregroundStyle(.secondary) }
          ForEach(results.indices, id: \.self) { index in
            let item = results[index]
            Button {
              usedCurrentLocation = false
              selection = JournalPlace(name: item.name ?? query,
                latitude: AutoLocationLogger.rounded(item.placemark.coordinate.latitude),
                longitude: AutoLocationLogger.rounded(item.placemark.coordinate.longitude))
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(item.name ?? "場所")
                if let address = item.placemark.title {
                  Text(address).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
      .navigationTitle("場所を追加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("この場所にする", icon: .checkmark) {
            if let selection { onSelect(selection); dismiss() }
          }.disabled(selection == nil)
        }
      }
      .task(id: query) {
        results = []
        message = nil
        isSearching = false
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
          try await Task.sleep(for: .milliseconds(350))
          isSearching = true
          let request = MKLocalSearch.Request()
          request.naturalLanguageQuery = trimmed
          let search = MKLocalSearch(request: request)
          let response = try await withTaskCancellationHandler {
            try await search.start()
          } onCancel: { search.cancel() }
          try Task.checkCancellation()
          results = response.mapItems
          message = results.isEmpty ? "場所が見つかりませんでした。検索語を変えてください。" : nil
          isSearching = false
        } catch {
          guard !Task.isCancelled else { return }
          isSearching = false
          message = "検索できませんでした。通信を確認して検索語を入力し直してください。"
        }
      }
    }
  }
}
