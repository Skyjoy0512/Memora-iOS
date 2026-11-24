import SwiftUI

/// Stable stored identifiers; records lead the visible workspace switcher.
enum ProjectWorkspaceTab: String, CaseIterable, Identifiable {
  case files
  case documents
  case sources
  case chat
  case images

  var id: String { rawValue }

  var title: String {
    switch self {
    case .files: "記録"
    case .documents: "資料"
    case .sources: "参考資料"
    case .chat: "チャット"
    case .images: "画像"
    }
  }

  var emptyTitle: LocalizedStringKey {
    switch self {
    case .files: "記録を追加"
    case .documents: "資料はまだありません"
    case .sources: "参考資料はまだありません"
    case .chat: "チャットを始める"
    case .images: "写真はまだありません"
    }
  }

  var emptyDescription: LocalizedStringKey {
    switch self {
    case .files: "録音や資料をこのプロジェクトにまとめると、ここから開けます。"
    case .documents: "頼むと、このプロジェクトの記録から資料やスライドを作れます。"
    case .sources: "リンク・ファイル・メモをまとめられます。"
    case .chat: "このプロジェクトの記録をAIに聞けます。"
    case .images: "記録のノートに写真を追加すると、ここにまとまります。"
    }
  }

  var emptyIcon: MemoraIcon {
    switch self {
    case .files: .waveform
    case .documents: .docText
    case .sources: .link
    case .chat: .chatBubble
    case .images: .photo
    }
  }

  var emptyActionTitle: LocalizedStringKey {
    switch self {
    case .files: "録音を追加"
    case .documents: "AIに資料を作ってもらう"
    case .sources: "参考資料を追加"
    case .chat: "新しいチャット"
    case .images: "記録を見る"
    }
  }

  var emptyActionIcon: MemoraIcon {
    switch self {
    case .files: .waveform
    case .documents: .docText
    case .sources: .plus
    case .chat: .squareAndPencil
    case .images: .waveform
    }
  }
}
