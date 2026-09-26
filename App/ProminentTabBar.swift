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
  /// The screen's create action, shown as a second round button that buds off
  /// the prominent button, directly above it.
  var contextualAction: ContextualCreateAction?
  @ViewBuilder var popover: PopoverContent

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var namespace
  /// Shared by the two buttons so their Liquid Glass shapes can merge and split.
  @Namespace private var glassNamespace

  var body: some View {
    let tabCount = Item.allCases.count
    let isSmall = tabCount <= 2

    // The create button is an overlay of the prominent button and is always
    // drawn. With no create action on the screen it sits exactly over the "＋"
    // (the glass reads as one shape); when there is one it lifts straight up,
    // and the two glass shapes part as it moves.
    MemoraGlassContainer(spacing: glassSpacing) {
      HStack(spacing: 10) {
        segmentedControl
          .padding(2)
          .frame(width: isSmall ? CGFloat(tabCount * 65) : nil)

        prominentButton
          .overlay(alignment: .top) {
            contextualOverlay
          }
      }
      .animation(reduceMotion ? nil : MemoraMotion.emphasis, value: isContextualShown)
      .animation(reduceMotion ? nil : MemoraMotion.emphasis, value: contextualSymbol)
    }
  }

  /// Smaller than the resting gap of the create button, so the two glass shapes
  /// only merge while the button is moving past the "＋".
  private var glassSpacing: CGFloat { 18 }
  private var splitGap: CGFloat { 21 }
  /// The prominent button's height plus the gap, so the create button rests just
  /// above it.
  private var splitDistance: CGFloat { prominentButtonHeight + splitGap }
  private var prominentButtonHeight: CGFloat { 60 }
  private var prominentButtonWidth: CGFloat { 48 }

  private var isContextualShown: Bool { contextualAction != nil }
  private var contextualSymbol: String { contextualAction?.symbol ?? prominentSymbol }

  @ViewBuilder
  private var contextualOverlay: some View {
    Button {
      contextualAction?.action()
    } label: {
      glassChrome(id: "contextual", circular: true) {
        Image(systemName: contextualSymbol)
          .font(.title3)
          .scaleEffect(0.95)
          .frame(width: prominentButtonWidth, height: prominentButtonWidth)
          .opacity(isContextualShown ? 1 : 0)
          .contentTransition(.symbolEffect(.replace))
          .accessibilityLabel(contextualAction?.title ?? "")
      }
    }
    .buttonStyle(.plain)
    .offset(y: isContextualShown ? -splitDistance : 0)
    .allowsHitTesting(isContextualShown)
    .accessibilityHidden(!isContextualShown)
  }

  /// Puts the Liquid Glass chrome on a button's label, with the identifier the
  /// container uses to merge and split the shapes.
  @ViewBuilder
  private func glassChrome<Content: View>(
    id: String,
    circular: Bool = false,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if #available(iOS 26.0, *) {
      if circular {
        content()
          .glassEffect(.regular.interactive(), in: .circle)
          .glassEffectID(id, in: glassNamespace)
      } else {
        content()
          .glassEffect(.regular.interactive(), in: .capsule)
          .glassEffectID(id, in: glassNamespace)
      }
    } else if circular {
      content()
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Circle())
        .overlay {
          Circle().stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
        }
    } else {
      content()
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .overlay {
          Capsule().stroke(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
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
      glassChrome(id: "prominent") {
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
      .font(.title)
      .scaleEffect(0.95)
      .frame(width: prominentButtonWidth, height: prominentButtonHeight)
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
