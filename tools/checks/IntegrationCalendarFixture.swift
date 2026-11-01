import Foundation

// These integration suites do not exercise EventKit. Calendar authorization
// has separate production checks in CalendarInterfaceChecks.
@MainActor enum CalendarService {
  enum Access { case granted, denied, unknown }
  static var access = Access.denied
}
