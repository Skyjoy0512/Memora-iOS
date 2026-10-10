import SwiftUI

protocol ProminentTabItem: CaseIterable, Hashable {
  var symbol: MemoraIcon { get }
  var filledSymbol: MemoraIcon { get }
  var title: String { get }
  var artwork: MemoraArtwork? { get }
  var filledArtwork: MemoraArtwork? { get }
}
