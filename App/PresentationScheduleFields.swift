import SwiftUI

struct PresentationScheduleFields: View {
  @Binding var slide: DocumentSlide

  var body: some View {
    if let schedule = slide.composition?.schedule {
      Section("期間と予定") {
        ForEach(schedule.entries) { entry in
          if let index = schedule.entries.firstIndex(where: { $0.id == entry.id }) {
            DisclosureGroup(entry.label) {
              TextField("予定名", text: entryLabel(index))
              Picker("開始", selection: period(index, start: true)) {
                ForEach(schedule.periods.indices, id: \.self) { Text(schedule.periods[$0]).tag($0) }
              }
              Picker("終了", selection: period(index, start: false)) {
                ForEach(schedule.periods.indices, id: \.self) { Text(schedule.periods[$0]).tag($0) }
              }
            }
          }
        }
      }
    }
  }

  private func entryLabel(_ index: Int) -> Binding<String> {
    Binding(get: { slide.composition?.schedule?.entries[index].label ?? "" },
      set: { slide.composition?.schedule?.entries[index].label = $0 })
  }
  private func period(_ index: Int, start: Bool) -> Binding<Int> {
    Binding(get: {
      guard let entries = slide.composition?.schedule?.entries, entries.indices.contains(index) else { return 0 }
      return start ? entries[index].start : entries[index].end
    }, set: { value in
      guard slide.composition?.schedule?.entries.indices.contains(index) == true else { return }
      if start { slide.composition?.schedule?.entries[index].start = value }
      else { slide.composition?.schedule?.entries[index].end = value }
    })
  }
}
