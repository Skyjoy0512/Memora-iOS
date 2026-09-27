import Foundation

/// One day of the journal with its records, newest first. Built once when the
/// records change, instead of regrouping every redraw.
struct LifeLogDayGroup: Identifiable, Equatable {
  var day: Date
  var entries: [LifeLogEntry]

  var id: Date { day }
}
