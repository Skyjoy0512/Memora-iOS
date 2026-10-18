import SwiftUI

/// Which projects the Library's project list shows. The personal workspace's
/// projects are all created here; shared projects come from CloudKit.
enum ProjectListFilter: String, CaseIterable, Identifiable {
  case all
  case mine
  case shared

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .all: "すべて"
    case .mine: "自分"
    case .shared: "共有"
    }
  }

  var emptyTitle: LocalizedStringKey {
    switch self {
    case .all: "プロジェクトはまだありません"
    case .mine: "自分のプロジェクトはありません"
    case .shared: "共有されたプロジェクトはありません"
    }
  }

  var emptyDetail: LocalizedStringKey {
    switch self {
    case .all, .mine: "右上の「作成」から始められます。"
    case .shared: "チームで共有されたプロジェクトがここに表示されます。"
    }
  }
}
