import SwiftUI

enum RootTab: String, Hashable, CaseIterable, Identifiable {
  // The order here is the order the tabs appear in, left to right. The raw
  // values stay the case names, so a reorder never changes a saved id.
  case files
  case home
  case tasks
  case askAI

  var id: Self { self }

  var title: String {
    switch self {
    case .home: "ジャーナル"
    case .files: "ファイル"
    case .askAI: "Ask AI"
    case .tasks: "タスク"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .home: .calendar
    case .files: .folder
    case .askAI: .chatBubble
    case .tasks: .checklist
    }
  }

  /// Only the active destination uses the filled silhouette.
  var filledSymbol: MemoraIcon {
    switch self {
    case .home: .calendarFill
    case .files: .folderFill
    case .askAI: .chatBubbleFill
    case .tasks: .checklistFill
    }
  }

  /// The colour of the light that greets each list tab at the top of the screen.
  var glowColor: Color {
    switch self {
    case .files: Color(red: 0.33, green: 0.55, blue: 0.98)
    case .home: Color(red: 0.97, green: 0.34, blue: 0.36)
    case .tasks: Color(red: 0.97, green: 0.80, blue: 0.30)
    case .askAI: .clear
    }
  }
}
