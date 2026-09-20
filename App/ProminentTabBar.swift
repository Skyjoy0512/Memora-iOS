import SwiftUI
import UIKit

protocol ProminentTabItem: CaseIterable, Hashable {
  var symbol: String { get }
  var title: String { get }
}

extension RootTab: ProminentTabItem {}

/// A floating tab bar whose destinations live in a segmented control, paired
/// with a single prominent button that opens a popover.
struct ProminentTabBar<Item: ProminentTabItem, PopoverContent: View>: View {
  @Binding var selection: Item
  /// Exposed so an empty state can open the popover without a tab tap.
  @Binding var isProminentPresented: Bool
  var prominentSymbol: String
  @ViewBuilder var popover: PopoverContent

  @Namespace private var namespace

  var body: some View {
    let tabCount = Item.allCases.count
    let isSmall = tabCount <= 2

    MemoraGlassContainer(spacing: 10) {
      HStack(spacing: 10) {
        segmentedControl
          .padding(2)
          .frame(width: isSmall ? CGFloat(tabCount * 65) : nil)

        prominentButton
      }
    }
  }

  @ViewBuilder
  private var segmentedControl: some View {
    let control = ProminentSegmentedControl(selection: $selection)

    if #available(iOS 26.0, *) {
      control.glassEffect(.regular.interactive(), in: .capsule)
    } else {
      control
        .background(.regularMaterial, in: Capsule())
        .overlay {
          Capsule().stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
        }
    }
  }

  @ViewBuilder
  private var prominentButton: some View {
    if #available(iOS 26.0, *) {
      Button {
        isProminentPresented = true
      } label: {
        prominentLabel
          .matchedTransitionSource(id: "prominentAction", in: namespace)
      }
      .buttonStyle(.glass)
      .popover(isPresented: $isProminentPresented) {
        popover
          .presentationCompactAdaptation(.popover)
          .navigationTransition(.zoom(sourceID: "prominentAction", in: namespace))
      }
    } else {
      Button {
        isProminentPresented = true
      } label: {
        prominentLabel
          .foregroundStyle(.primary)
          .background(Color.primary.opacity(0.08), in: Circle())
          .matchedTransitionSource(id: "prominentAction", in: namespace)
      }
      .buttonStyle(.plain)
      .popover(isPresented: $isProminentPresented) {
        popover
          .presentationCompactAdaptation(.popover)
          .navigationTransition(.zoom(sourceID: "prominentAction", in: namespace))
      }
    }
  }

  private var prominentLabel: some View {
    Image(systemName: prominentSymbol)
      .font(.title)
      .scaleEffect(0.95)
      .frame(width: 44, height: 55)
      .accessibilityLabel("作成メニューを開く")
  }
}

/// The destinations, drawn in SwiftUI rather than `UISegmentedControl`: one
/// tappable segment each, so a tap always lands on the tab under the finger.
private struct ProminentSegmentedControl<Item: ProminentTabItem>: View {
  @Binding var selection: Item
  @Namespace private var pill

  private var allTabs: [Item] { Array(Item.allCases) }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(allTabs, id: \.self) { item in
        segment(item)
      }
    }
    .animation(.smooth(duration: 0.25), value: selection)
  }

  private func segment(_ item: Item) -> some View {
    let isSelected = item == selection

    return Button {
      selection = item
    } label: {
      VStack(spacing: 4) {
        Image(systemName: item.symbol)
          .font(.title3)
          .fontWeight(.regular)
          .symbolVariant(.fill)
          .frame(height: 25)

        Text(item.title)
          .font(.caption2)
      }
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity)
      .frame(height: 66)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background {
      if isSelected {
        Capsule()
          .fill(Color(uiColor: .secondarySystemFill))
          .padding(2)
          .matchedGeometryEffect(id: "segmentPill", in: pill)
      }
    }
    .accessibilityLabel(item.title)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}
