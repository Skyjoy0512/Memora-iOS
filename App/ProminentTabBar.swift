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
  /// The height of the bar's row and the diameter of the prominent button. One
  /// place, so the composer and the bar stay the same height.
  static var barHeight: CGFloat { 56 }

  @Binding var selection: Item
  /// Exposed so an empty state can open the popover without a tab tap.
  @Binding var isProminentPresented: Bool
  var prominentSymbol: String
  @ViewBuilder var popover: PopoverContent

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

  /// The prominent button, one round Liquid Glass control.
  @ViewBuilder
  private func glassChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    if #available(iOS 26.0, *) {
      content()
        .glassEffect(.regular.interactive(), in: .circle)
    } else {
      content()
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Circle())
        .overlay {
          Circle().stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
        }
    }
  }

  @ViewBuilder
  private var segmentedControl: some View {
    // At the largest text sizes the segment labels no longer fit on one row, so
    // the tabs drop to their symbols; the names stay as accessibility labels.
    let showsTitles = !dynamicTypeSize.isAccessibilitySize
    let control = ProminentSegmentedControl(
      selection: $selection,
      colorScheme: colorScheme,
      showsTitles: showsTitles
    )

    if #available(iOS 26.0, *) {
      // The system control draws and animates its Liquid Glass selection
      // bubble; the glass keeps the capsule the design intends. It is not
      // `interactive()` — that press layer sat over the control and swallowed
      // taps, which made switching tabs feel unresponsive.
      control.glassEffect(.regular, in: .capsule)
    } else {
      control
        .background(.regularMaterial, in: Capsule())
        .overlay {
          Capsule().stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
        }
    }
  }

  private var prominentButton: some View {
    Button {
      isProminentPresented = true
    } label: {
      glassChrome {
        prominentLabel
      }
      .matchedTransitionSource(id: "prominentAction", in: namespace)
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isProminentPresented) {
      popover
        .presentationCompactAdaptation(.popover)
        .navigationTransition(.zoom(sourceID: "prominentAction", in: namespace))
    }
  }

  private var prominentLabel: some View {
    Image(systemName: prominentSymbol)
      .font(.system(size: 22, weight: .medium))
      .frame(width: Self.barHeight, height: Self.barHeight)
      .accessibilityLabel("作成メニューを開く")
  }
}

/// The tabs are drawn by `UISegmentedControl` so the selection keeps the system's
/// Liquid Glass bubble and its morph, with each segment rendered as an icon over
/// its title.
private struct ProminentSegmentedControl<Item: ProminentTabItem>: UIViewRepresentable {
  @Binding var selection: Item
  var colorScheme: ColorScheme
  /// Draws the title under each symbol, or symbols only at the largest sizes.
  var showsTitles: Bool
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
    control.selectedSegmentTintColor = UIColor.secondarySystemFill
    control.addTarget(context.coordinator, action: #selector(Coordinator.didChange(_:)), for: .valueChanged)
    context.coordinator.appliedColorScheme = colorScheme
    context.coordinator.appliedShowsTitles = showsTitles
    return control
  }

  func updateUIView(_ uiView: UISegmentedControl, context: Context) {
    // Never move the selection while a finger is down: doing so cancels the
    // touch in progress, which is what swallowed the first tap on a tab.
    if !uiView.isTracking,
       let index = allTabs.firstIndex(of: selection),
       uiView.selectedSegmentIndex != index {
      // An external change (the sidebar, a deep link) arrives programmatically;
      // animating it drives the control's own Liquid Glass morph.
      UIView.animate(
        withDuration: 0.35,
        delay: 0,
        usingSpringWithDamping: 0.82,
        initialSpringVelocity: 0
      ) {
        uiView.selectedSegmentIndex = index
        uiView.layoutIfNeeded()
      }
    }

    // The rendered images bake in the text color, so redraw them when the
    // appearance changes instead of leaving last mode's colors behind. The
    // labels are redrawn too when they switch to symbols only.
    if context.coordinator.appliedColorScheme != colorScheme
      || context.coordinator.appliedShowsTitles != showsTitles {
      context.coordinator.appliedColorScheme = colorScheme
      context.coordinator.appliedShowsTitles = showsTitles
      for (index, item) in allTabs.enumerated() {
        uiView.setImage(generatedImage(for: item), forSegmentAt: index)
      }
    }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: UISegmentedControl,
    context: Context
  ) -> CGSize? {
    CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: 52)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection)
  }

  final class Coordinator: NSObject {
    @Binding var selection: Item
    var appliedColorScheme: ColorScheme?
    var appliedShowsTitles: Bool?

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
    let label = VStack(spacing: 3) {
      Image(systemName: item.symbol)
        .font(.subheadline)
        .fontWeight(.regular)
        .symbolVariant(.fill)
        .frame(height: 19)

      if showsTitles {
        Text(item.title)
          .font(.caption2)
          .lineLimit(1)
      }
    }
    .environment(\.colorScheme, colorScheme)

    let renderer = ImageRenderer(content: label)
    renderer.scale = displayScale
    // The segments are images, so UIKit has no title to read out. Naming the
    // image is what VoiceOver reads for that segment.
    let image = renderer.uiImage
    image?.accessibilityLabel = item.title
    return image
  }
}
