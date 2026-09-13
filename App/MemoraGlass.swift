import SwiftUI

/// Groups Liquid Glass surfaces so they blend and morph together.
///
/// Falls back to a plain layout before Liquid Glass existed, because the
/// project still deploys to iOS 18.
struct MemoraGlassContainer<Content: View>: View {
  var spacing: CGFloat = 12
  @ViewBuilder var content: () -> Content

  var body: some View {
    if #available(iOS 26.0, *) {
      GlassEffectContainer(spacing: spacing) {
        content()
      }
    } else {
      content()
    }
  }
}

extension View {
  /// Puts a view on the floating control layer with Liquid Glass.
  ///
  /// Reserve this for navigation and controls that hover over content. The HIG
  /// asks that the content layer keep using standard materials instead.
  @ViewBuilder
  func memoraGlass(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
    if #available(iOS 26.0, *) {
      background {
        // Backs the glass so foreground labels stay legible over busy content.
        // A tint means the surface is meant to read as solid and prominent.
        if let tint {
          shape.fill(tint)
        } else {
          shape.fill(.ultraThinMaterial)
        }
      }
      .glassEffect(glass(tint: tint, interactive: interactive), in: shape)
    } else {
      background(.regularMaterial, in: shape)
        .background(tint ?? .clear, in: shape)
        .overlay {
          shape.stroke(Color(uiColor: .separator).opacity(0.7), lineWidth: 0.5)
        }
    }
  }

  @available(iOS 26.0, *)
  private func glass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint {
      glass = glass.tint(tint)
    }
    if interactive {
      glass = glass.interactive()
    }
    return glass
  }
}
