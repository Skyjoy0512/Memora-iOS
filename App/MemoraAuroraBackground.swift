// Portions derived from Google ADK Recipes, Copyright 2026 Google LLC.
// Adapted for Memora: SwiftUI Canvas, top-aligned geometry, monotonic motion and power policies.
// Licensed under Apache-2.0. See Resources/GoogleADKRecipes-LICENSE.txt.

import SwiftUI

struct MemoraAuroraBackground: View {
  var isThinking: Bool
  /// Optional normalized input for a future voice surface.
  var energy: Double = 0

  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @State private var usesStaticFrame = Self.prefersStaticFrame
  @State private var clock = AuroraAnimationState()
  @State private var retainsCanvas = false
  @State private var isLit = false

  static let fadeDuration: Double = 0.55
  nonisolated private static let unitCircle = Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))
  private static let lowerFade = LinearGradient(stops: [
    .init(color: .white, location: 0), .init(color: .white, location: 0.38),
    .init(color: .clear, location: 1)
  ], startPoint: .top, endPoint: .bottom)

  private var canDisplay: Bool { scenePhase == .active && !reduceTransparency }
  private var canAnimate: Bool { canDisplay && isThinking && !reduceMotion && !usesStaticFrame }

  var body: some View {
    GeometryReader { proxy in
      if canDisplay {
        ZStack(alignment: .top) {
          if retainsCanvas {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !canAnimate)) { _ in
              canvas(phase: clock.phase(at: .now))
            }
            .frame(height: proxy.size.height * 0.60)
            .mask(Self.lowerFade)
            .opacity(isLit ? 1 : 0)
            .transition(.opacity)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onChange(of: canAnimate, initial: true) { _, running in
      clock.setRunning(running, at: .now)
    }
    .onChange(of: isThinking, initial: true) { _, thinking in
      withAnimation(reduceMotion ? nil : .easeInOut(duration: Self.fadeDuration)) {
        isLit = thinking
        if thinking { retainsCanvas = true }
      }
    }
    .task(id: isThinking) {
      guard !isThinking else { return }
      if !reduceMotion { try? await Task.sleep(for: .seconds(Self.fadeDuration)) }
      guard !Task.isCancelled else { return }
      retainsCanvas = false
      clock = AuroraAnimationState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
      usesStaticFrame = Self.prefersStaticFrame
    }
    .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
      usesStaticFrame = Self.prefersStaticFrame
    }
  }

  private static var prefersStaticFrame: Bool {
    let info = ProcessInfo.processInfo
    return info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical
  }

  private func canvas(phase: Double) -> some View {
    let palette = colorScheme == .dark ? AuroraPalette.dark : .light
    let energy = energy.isFinite ? min(1, max(0, energy)) : 0
    return Canvas(rendersAsynchronously: true) { context, size in
      guard size.width > 0, size.height > 0 else { return }
      let w = size.width, h = size.height
      let lift = energy * h * 0.14
      let scale = 1 + energy * 0.45
      let breath = sin(phase * 0.72)
      var context = context
      context.blendMode = .screen
      context.opacity = 0.94 + breath * 0.06
      Self.draw(context, palette.center, x: w * 0.5, y: h * (0.24 + 0.025 * breath) - lift * 0.6,
        rx: w * 0.91, ry: h * (0.82 + energy * 0.16))
      Self.draw(context, palette.left, x: w * (0.24 + sin(phase) * 0.09), y: h * (0.28 + 0.036 * cos(phase)) - lift * 0.85,
        rx: w * 0.55 * scale, ry: h * 0.69 * scale)
      Self.draw(context, palette.right, x: w * (0.75 + cos(phase * 0.85) * 0.09), y: h * (0.19 + 0.045 * sin(phase * 0.85)) - lift,
        rx: w * 0.58 * scale, ry: h * 0.76 * scale)
      Self.draw(context, palette.ice, x: w * (0.52 + sin(phase * 0.65) * 0.045), y: h * 0.31 - lift * 1.05,
        rx: w * 0.43 * scale, ry: h * 0.62 * scale)
    }
  }

  private nonisolated static func draw(_ context: GraphicsContext, _ gradient: Gradient,
                                       x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat) {
    var context = context
    context.translateBy(x: x, y: y)
    context.scaleBy(x: rx, y: ry)
    context.fill(unitCircle, with: .radialGradient(gradient, center: .zero, startRadius: 0.04, endRadius: 1))
  }
}
