import SwiftUI

protocol ProminentTabItem: CaseIterable, Hashable {
  var symbol: MemoraIcon { get }
  var filledSymbol: MemoraIcon { get }
  var title: String { get }
}
