import SwiftUI
import UIKit

protocol ProminentTabItem: CaseIterable, Hashable {
  var symbol: String { get }
  var title: String { get }
}

extension RootTab: ProminentTabItem {}

/// A round glass button that sits between the tabs and the prominent button, for
/// one extra top-level action such as Ask AI.
struct ProminentTabSecondaryAction {
  var symbol: String
  var accessibilityLabel: String
  var action: () -> Void
}

/// A floating tab bar whose destinations live in a segmented control, paired
/// with a single prominent button that opens a popover.
struct ProminentTabBar<Item: ProminentTabItem, PopoverContent: View>: View {
  @Binding var selection: Item
  /// Exposed so an empty state can open the popover without a tab tap.
  @Binding var isProminentPresented: Bool
  var prominentSymbol: String
  /// An extra round action between the tabs and the prominent button, if any.
  var secondaryAction: ProminentTabSecondaryAction?
  /// The screen's create action, shown as a second round button that buds off
  /// the prominent button, directly above it.
  var contextualAction: ContextualCreateAction?
  /// Shared with the presenting screen so the extra action can zoom open.
  var secondaryTransitionNamespace: Namespace.ID?
  @ViewBuilder var popover: PopoverContent

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var namespace

  var body: some View {
    let tabCount = Item.allCases.count
    let isSmall = tabCount <= 2

    MemoraGlassContainer(spacing: 10) {
      VStack(spacing: 21) {
        // The create button buds off the prominent button: same size, centred on
        // it, and it rises straight up out of it.
        if let contextualAction {
          contextualButton(contextualAction)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transition(splitTransition)
        }

        HStack(spacing: 10) {
          segmentedControl
            .padding(2)
            .frame(width: isSmall ? CGFloat(tabCount * 65) : nil)

          if let secondaryAction {
            secondaryButton(secondaryAction)
          }

          prominentButton
        }
      }
    }
  }

  /// Grows out of the prominent button straight up: it starts over the button and
  /// slides to its place while it scales up, rather than appearing from a corner.
  private var splitTransition: AnyTransition {
    guard !reduceMotion else { return .opacity }
    return .offset(y: 55 + 21)
      .combined(with: .scale(scale: 0.2, anchor: .bottom))
      .combined(with: .opacity)
  }

  @ViewBuilder
  private func contextualButton(_ action: ContextualCreateAction) -> some View {
    if #available(iOS 26.0, *) {
      Button(action: action.action) {
        contextualLabel(action)
      }
      .buttonStyle(.glass)
    } else {
      Button(action: action.action) {
        contextualLabel(action)
          .foregroundStyle(.primary)
          .background(Color.primary.opacity(0.08), in: Circle())
      }
      .buttonStyle(.plain)
    }
  }

  /// Matches the prominent button's size so the two read as one shape that
  /// splits.
  private func contextualLabel(_ action: ContextualCreateAction) -> some View {
    Image(systemName: action.symbol)
      .font(.title)
      .scaleEffect(0.95)
      .frame(width: 44, height: 55)
      .accessibilityLabel(action.title)
  }

  @ViewBuilder
  private func secondaryButton(_ action: ProminentTabSecondaryAction) -> some View {
    if #available(iOS 26.0, *) {
      Button(action: action.action) {
        transitionSource {
          secondaryLabel(action)
        }
      }
      .buttonStyle(.glass)
    } else {
      Button(action: action.action) {
        transitionSource {
          secondaryLabel(action)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(0.08), in: Circle())
        }
      }
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private func transitionSource<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    if let secondaryTransitionNamespace {
      content()
        .matchedTransitionSource(id: "secondaryAction", in: secondaryTransitionNamespace)
    } else {
      content()
    }
  }

  private func secondaryLabel(_ action: ProminentTabSecondaryAction) -> some View {
    Image(systemName: action.symbol)
      .font(.title)
      .scaleEffect(0.95)
      .frame(width: 44, height: 55)
      .accessibilityLabel(action.accessibilityLabel)
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

    applySegmentLabels(uiView)
  }

  /// The segments are images, so UIKit has no names to read out. Label each
  /// segment view itself, which is what VoiceOver enumerates.
  private func applySegmentLabels(_ control: UISegmentedControl) {
    let labels = allTabs.map(\.title)
    let selected = allTabs.firstIndex(of: selection)

    guard control.subviews.count == labels.count else { return }

    for (index, segment) in control.subviews.enumerated() {
      segment.isAccessibilityElement = true
      segment.accessibilityLabel = labels[index]
      segment.accessibilityTraits = index == selected ? [.button, .selected] : .button
    }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: UISegmentedControl,
    context: Context
  ) -> CGSize? {
    CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: 66)
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
    let label = VStack(spacing: 4) {
      Image(systemName: item.symbol)
        .font(.title3)
        .fontWeight(.regular)
        .symbolVariant(.fill)
        .frame(height: 25)

      if showsTitles {
        Text(item.title)
          .font(.caption2)
          .lineLimit(1)
      }
    }
    .environment(\.colorScheme, colorScheme)

    let renderer = ImageRenderer(content: label)
    renderer.scale = displayScale
    return renderer.uiImage
  }
}
