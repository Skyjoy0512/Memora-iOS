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

/// The destinations, drawn in SwiftUI: one tappable segment each — so a tap
/// always lands on the tab under the finger — with one selection capsule that
/// slides between them through `matchedGeometryEffect`.
private struct ProminentSegmentedControl<Item: ProminentTabItem>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var selection: Item
  @Namespace private var pill
  /// Shared press state, so the whole glass capsule squishes while any segment
  /// is held, the way interactively lit glass does.
  @State private var isPressed = false

  private let height: CGFloat = 66
  private let pillInset: CGFloat = 2

  private var tabs: [Item] { Array(Item.allCases) }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(tabs, id: \.self) { item in
        segment(item)
      }
    }
    .frame(height: height)
    .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isPressed)
  }

  private func segment(_ item: Item) -> some View {
    let isSelected = item == selection

    return Button {
      guard selection != item else { return }
      withAnimation(reduceMotion ? nil : MemoraMotion.tabSelection) {
        selection = item
      }
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
      .frame(height: height)
      .contentShape(Rectangle())
      .background {
        if isSelected {
          Capsule()
            .fill(Color(uiColor: .secondarySystemFill))
            .padding(pillInset)
            .matchedGeometryEffect(id: "segmentPill", in: pill)
        }
      }
    }
    .buttonStyle(SegmentPressStyle(isPressed: $isPressed, reduceMotion: reduceMotion))
    .accessibilityLabel(item.title)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

/// Reports whether the segment is held so the glass can react, and gives the
/// segment's own content a small press.
private struct SegmentPressStyle: ButtonStyle {
  @Binding var isPressed: Bool
  var reduceMotion: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
      .animation(reduceMotion ? nil : MemoraMotion.control, value: configuration.isPressed)
      .onChange(of: configuration.isPressed) { _, newValue in
        isPressed = newValue
      }
  }
}
