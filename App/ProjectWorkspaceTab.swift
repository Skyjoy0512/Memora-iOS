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
    case .chat: "チャットを始める"
    case .files: "ファイルを追加"
    case .sources: "ソースを追加"
    }
  }

  var emptyDescription: LocalizedStringKey {
    switch self {
    case .chat: "このプロジェクトの記録について質問できます。会話はここに残ります。"
    case .files: "録音や資料をこのプロジェクトにまとめると、ここから開けます。"
    case .sources: "リンク・ファイル・メモを追加すると、AIの参照候補になります。"
    }
  }

  var emptyIcons: [MemoraIcon] {
    switch self {
    case .chat: [.chatBubble, .sparkles, .doc]
    case .files: [.waveform, .doc, .folder]
    case .sources: [.link, .doc, .photo]
    }
  }

  var emptyActionTitle: LocalizedStringKey {
    switch self {
    case .chat: "新しいチャット"
    case .files: "録音を追加"
    case .sources: "ソースを追加"
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
