import SwiftUI
import UIKit

extension RootTab: ProminentTabItem {}

/// A floating tab bar whose destinations live in a segmented control, paired
/// with a single prominent button that opens a popover.
struct ProminentTabBar<Item: ProminentTabItem, PopoverContent: View>: View {
  /// The height of the bar's row and the diameter of the prominent button.
  static var barHeight: CGFloat { MemoraBarMetrics.height }
  /// The `.glass` button style pads its label, so the symbol's frame is smaller
  /// than the bar for the finished circle to match the bar's height.
  private static var glassLabelSide: CGFloat { barHeight - 14 }

  @Binding var selection: Item
  /// Exposed so an empty state can open the popover without a tab tap.
  @Binding var isProminentPresented: Bool
  var prominentSymbol: MemoraIcon
  @ViewBuilder var popover: PopoverContent

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
      showsTitles: showsTitles,
      dynamicTypeSize: dynamicTypeSize,
      reduceMotion: reduceMotion
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

  @ViewBuilder
  private var prominentButton: some View {
    if #available(iOS 26.0, *) {
      // The system glass button plus a zoom popover sourced from its symbol is
      // what lets the button's Liquid Glass morph into the menu.
      Button {
        isProminentPresented = true
      } label: {
        prominentLabel
          .frame(width: Self.glassLabelSide, height: Self.glassLabelSide)
          .matchedTransitionSource(id: "prominentAction", in: namespace)
      }
      .buttonStyle(.glass)
      .buttonBorderShape(.circle)
      .popover(isPresented: $isProminentPresented) {
        popover
          .presentationCompactAdaptation(.popover)
          .navigationTransition(.zoom(sourceID: "prominentAction", in: namespace))
      }
    } else {
      Button {
        isProminentPresented = true
      } label: {
        glassChrome {
          prominentLabel
            .frame(width: Self.barHeight, height: Self.barHeight)
        }
      }
      .buttonStyle(.plain)
      .popover(isPresented: $isProminentPresented) {
        popover.presentationCompactAdaptation(.popover)
      }
    }
  }

  private var prominentLabel: some View {
    Image(icon: prominentSymbol)
      .font(.system(size: 22, weight: .medium))
      .rotationEffect(.degrees(isProminentPresented && prominentSymbol == .plus ? 45 : 0))
      .animation(reduceMotion ? nil : MemoraMotion.control, value: isProminentPresented)
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
  var dynamicTypeSize: DynamicTypeSize
  var reduceMotion: Bool
  @Environment(\.displayScale) private var displayScale

  private var allTabs: [Item] { Array(Item.allCases) }

  func makeUIView(context: Context) -> UISegmentedControl {
    let control = UISegmentedControl()
    context.coordinator.parent = self
    context.coordinator.prepareImages()

    for (index, item) in allTabs.enumerated() {
      if let image = context.coordinator.image(at: index, selected: item == selection) {
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
    context.coordinator.appliedDynamicTypeSize = dynamicTypeSize
    context.coordinator.appliedDisplayScale = displayScale
    context.coordinator.appliedSelection = selection
    return control
  }

  func updateUIView(_ uiView: UISegmentedControl, context: Context) {
    context.coordinator.parent = self
    // Never move the selection while a finger is down: doing so cancels the
    // touch in progress, which is what swallowed the first tap on a tab.
    if !uiView.isTracking,
       let index = allTabs.firstIndex(of: selection),
       uiView.selectedSegmentIndex != index {
      // An external change (the sidebar, a deep link) arrives programmatically;
      // animating it drives the control's own Liquid Glass morph.
      if reduceMotion {
        uiView.selectedSegmentIndex = index
      } else {
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
    }

    // The rendered images bake in the text color, so redraw them when the
    // appearance changes instead of leaving last mode's colors behind. The
    // labels are redrawn too when they switch to symbols only.
    if context.coordinator.appliedColorScheme != colorScheme
      || context.coordinator.appliedShowsTitles != showsTitles
      || context.coordinator.appliedDynamicTypeSize != dynamicTypeSize
      || context.coordinator.appliedDisplayScale != displayScale {
      context.coordinator.appliedColorScheme = colorScheme
      context.coordinator.appliedShowsTitles = showsTitles
      context.coordinator.appliedDynamicTypeSize = dynamicTypeSize
      context.coordinator.appliedDisplayScale = displayScale
      context.coordinator.prepareImages()
      context.coordinator.applyImages(to: uiView)
    } else if context.coordinator.appliedSelection != selection {
      context.coordinator.applyImages(to: uiView)
    }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: UISegmentedControl,
    context: Context
  ) -> CGSize? {
    // The row adds 2pt padding top and bottom around this control, so the
    // control is 4pt shorter than the bar and the row lands at the bar's height.
    CGSize(
      width: proposal.replacingUnspecifiedDimensions().width,
      height: MemoraBarMetrics.height - 4
    )
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject {
    var parent: ProminentSegmentedControl
    var appliedColorScheme: ColorScheme?
    var appliedShowsTitles: Bool?
    var appliedDynamicTypeSize: DynamicTypeSize?
    var appliedDisplayScale: CGFloat?
    var appliedSelection: Item?
    private var outlineImages: [UIImage?] = []
    private var filledImages: [UIImage?] = []

    init(parent: ProminentSegmentedControl) {
      self.parent = parent
    }

    // Rendering stays out of the touch handler so changing the glyph never
    // delays the segmented control's own selection animation.
    func prepareImages() {
      outlineImages = parent.allTabs.map { parent.generatedImage(for: $0, selected: false) }
      filledImages = parent.allTabs.map { parent.generatedImage(for: $0, selected: true) }
    }

    func image(at index: Int, selected: Bool) -> UIImage? {
      selected ? filledImages[index] : outlineImages[index]
    }

    func applyImages(to control: UISegmentedControl) {
      for (index, _) in parent.allTabs.enumerated() {
        control.setImage(image(at: index, selected: index == control.selectedSegmentIndex), forSegmentAt: index)
      }
      appliedSelection = parent.allTabs.indices.contains(control.selectedSegmentIndex)
        ? parent.allTabs[control.selectedSegmentIndex] : nil
    }

    @objc func didChange(_ control: UISegmentedControl) {
      let tabs = Array(Item.allCases)
      let index = control.selectedSegmentIndex
      guard tabs.indices.contains(index) else { return }
      parent.selection = tabs[index]
      applyImages(to: control)
    }
  }

  private func generatedImage(for item: Item, selected: Bool) -> UIImage? {
    let label = VStack(spacing: 3) {
      Image(icon: selected ? item.filledSymbol : item.symbol)
        .font(.system(size: 18))
        .foregroundStyle(.primary)

      if showsTitles {
        Text(item.title)
          .font(.caption2)
          .lineLimit(1)
      }
    }
    .environment(\.colorScheme, colorScheme)
    .environment(\.dynamicTypeSize, dynamicTypeSize)

    let renderer = ImageRenderer(content: label)
    renderer.scale = displayScale
    // The segments are images, so UIKit has no title to read out. Naming the
    // image is what VoiceOver reads for that segment. Original rendering keeps
    // the glyph label-black instead of letting the segment's tint grey it out.
    let image = renderer.uiImage?.withRenderingMode(.alwaysOriginal)
    image?.accessibilityLabel = item.title
    return image
  }
}
