import SwiftUI

/// The three surfaces of a project workspace. The order is the order the tab
/// bar shows; chat comes first because a project is usually opened to ask
/// something about it.
enum ProjectWorkspaceTab: String, CaseIterable, Identifiable {
  case chat
  case files
  case sources

  var id: String { rawValue }

  var title: String {
    switch self {
    case .chat: "チャット"
    case .files: "記録"
    case .sources: "参考資料"
    }
  }

  var emptyTitle: LocalizedStringKey {
    switch self {
    case .chat: "チャットを始める"
    case .files: "記録を追加"
    case .sources: "参考資料を追加"
    }
  }

  var emptyDescription: LocalizedStringKey {
    switch self {
    case .chat: "このプロジェクトの記録をAIに聞けます。"
    case .files: "録音や資料をこのプロジェクトにまとめると、ここから開けます。"
    case .sources: "リンク・ファイル・メモをまとめられます。"
    }
  }

  var emptyIcon: MemoraIcon {
    switch self {
    case .chat: .chatBubble
    case .files: .waveform
    case .sources: .link
    }
  }

  var emptyActionTitle: LocalizedStringKey {
    switch self {
    case .chat: "新しいチャット"
    case .files: "録音を追加"
    case .sources: "参考資料を追加"
    }
  }

  var emptyActionIcon: MemoraIcon {
    switch self {
    case .chat: .squareAndPencil
    case .files: .waveform
    case .sources: .plus
    }
  }
}
