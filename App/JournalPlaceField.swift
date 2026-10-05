import SwiftUI

struct JournalPlaceField: View {
  @Binding var name: String
  @Binding var place: JournalPlace?
  @State private var isPicking = false

  var body: some View {
    Section("場所（任意）") {
      TextField("場所名を手入力", text: $name)
        .onChange(of: name) { _, newName in
          if let place, newName != place.name { self.place = nil }
        }
      Button(place == nil ? "場所を追加" : "場所を変更") { isPicking = true }
        .sheet(isPresented: $isPicking) {
          JournalPlacePicker { selected in
            place = selected
            name = selected.name
          }
        }
      if let place { JournalMapPreview(place: place) }
      if !name.isEmpty || place != nil {
        Button("場所を削除", role: .destructive) { name = ""; place = nil }
      }
    }
  }
}
