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
    case .files: "ファイル"
    case .sources: "ソース"
    }
  }

  var emptyTitle: LocalizedStringKey {
    switch self {
    case .chat: "チャットはまだありません"
    case .files: "ファイルはまだありません"
    case .sources: "ソースはまだありません"
    }
  }

  var emptyDescription: LocalizedStringKey {
    switch self {
    case .chat: "このプロジェクトについて質問すると、会話がここに残ります。"
    case .files: "録音や資料をこのプロジェクトへ追加すると、ここに並びます。"
    case .sources: "リンク・ファイル・メモを追加すると、AIの参照候補になります。"
    }
  }

  var emptyIcon: MemoraIcon {
    switch self {
    case .chat: .chatBubble
    case .files: .folder
    case .sources: .doc
    }
  }
}
