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
      }
      .buttonStyle(.plain)
      .popover(isPresented: $isProminentPresented) {
        popover
          .presentationCompactAdaptation(.popover)
      }
    }
  }

  private var prominentLabel: some View {
    Image(systemName: prominentSymbol)
      .font(.title)
      .scaleEffect(0.95)
      .frame(width: 40, height: 50)
  }
}

/// The tabs are drawn by `UISegmentedControl` so the selection pill matches the
/// system, with each segment rendered as an icon over its title.
private struct ProminentSegmentedControl<Item: ProminentTabItem>: UIViewRepresentable {
  @Binding var selection: Item
  @Environment(\.displayScale) private var displayScale

  private var allTabs: [Item] { Array(Item.allCases) }

  func makeUIView(context: Context) -> UISegmentedControl {
    let control = UISegmentedControl()

    for (index, item) in allTabs.enumerated() {
      if let image = generatedImage(for: item) {
        control.insertSegment(with: image, at: index, animated: false)
      } else {
        control.insertSegment(withTitle: item.title, at: index, animated: false)
      }
    }

    control.selectedSegmentIndex = allTabs.firstIndex(of: selection) ?? 0
    control.selectedSegmentTintColor = UIColor(Color.gray.opacity(0.18))
    control.addTarget(context.coordinator, action: #selector(Coordinator.didChange(_:)), for: .valueChanged)
    return control
  }

  func updateUIView(_ uiView: UISegmentedControl, context: Context) {
    if let index = allTabs.firstIndex(of: selection), uiView.selectedSegmentIndex != index {
      uiView.selectedSegmentIndex = index
    }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: UISegmentedControl,
    context: Context
  ) -> CGSize? {
    CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: 60)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection)
  }

  final class Coordinator: NSObject {
    @Binding var selection: Item

    init(selection: Binding<Item>) {
      _selection = selection
    }

    @objc func didChange(_ control: UISegmentedControl) {
      let tabs = Array(Item.allCases)
      let index = control.selectedSegmentIndex
      guard tabs.indices.contains(index) else { return }
      selection = tabs[index]
    }
  }

  private func generatedImage(for item: Item) -> UIImage? {
    let renderer = ImageRenderer(content: VStack(spacing: 4) {
      Image(systemName: item.symbol)
        .font(.title3)
        .fontWeight(.regular)
        .symbolVariant(.fill)
        .frame(height: 25)

      Text(item.title)
        .font(.caption2)
    })
    renderer.scale = displayScale
    return renderer.uiImage
  }
}
