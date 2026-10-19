import SwiftUI

/// A short, skippable introduction. Three pages, then straight into recording.
struct OnboardingView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var startRecording: () -> Void
  var showSample: () -> Void
  var skip: () -> Void

  @State private var page = OnboardingPage.record
  @State private var isOccupationSelectionPresented = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()
        Button("スキップ", action: skip)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
          .opacity(isLastPage ? 0 : 1)
          .accessibilityHidden(isLastPage)
      }
      .padding(.horizontal, MemoraSpacing.xxl)
      .padding(.top, MemoraSpacing.sm)

      TabView(selection: $page) {
        ForEach(OnboardingPage.allCases) { item in
          OnboardingPageView(page: item, isCurrent: item == page)
            .tag(item)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))

      PageIndicator(current: page)
        .padding(.bottom, MemoraSpacing.xxl)

      actions
        .padding(.horizontal, MemoraSpacing.xxl)
        .frame(minHeight: 132, alignment: .top)

      Label("録音はまず、このiPhoneに保存されます", icon: .lockShield)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, MemoraSpacing.lg)
        .padding(.bottom, MemoraSpacing.md)
    }
    .background(Color(uiColor: .systemBackground))
    .animation(reduceMotion ? nil : MemoraMotion.screen, value: page)
    .sheet(isPresented: $isOccupationSelectionPresented) {
      NavigationStack {
        OccupationSelectionView()
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("完了") { isOccupationSelectionPresented = false }
            }
          }
      }
    }
  }

  @ViewBuilder
  private var actions: some View {
    VStack(spacing: 12) {
      Button(action: primaryAction) {
        Text(isLastPage ? "最初の会話を録音" : "次へ")
          .font(.headline)
          .contentTransition(.opacity)
          .frame(maxWidth: .infinity)
          .padding(.vertical, MemoraSpacing.lg)
          .foregroundStyle(.white)
          .background(.tint, in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
          .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
      }
      .buttonStyle(.plain)

      if isLastPage {
        VStack(spacing: 2) {
          Button("仕事・活動を選ぶ（任意）") { isOccupationSelectionPresented = true }
            .font(.subheadline)
          Button("サンプルで見る", action: showSample)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MemoraSpacing.sm)

          Button("このiPhoneで始める", action: skip)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MemoraSpacing.xs)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
  }

  private var isLastPage: Bool {
    page == OnboardingPage.allCases.last
  }

  private func primaryAction() {
    if isLastPage {
      startRecording()
    } else if let next = page.next {
      page = next
    }
  }
}

private struct OnboardingPageView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var page: OnboardingPage
  var isCurrent: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer(minLength: 0)
        .frame(maxHeight: 72)

      Image(icon: page.symbol, size: 38)
        .font(.system(size: 38, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 78, height: 78)
        .background(.tint, in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
        .scaleEffect(isCurrent || reduceMotion ? 1 : 0.86)
        .animation(reduceMotion ? nil : MemoraMotion.emphasis, value: isCurrent)
        .accessibilityHidden(true)

      Text(page.title)
        .font(.largeTitle.bold())
        .tracking(-0.8)
        .padding(.top, MemoraSpacing.section)

      Text(page.detail)
        .font(.title3)
        .foregroundStyle(.secondary)
        .lineSpacing(3)
        .padding(.top, MemoraSpacing.lg)

      OnboardingPreview(page: page, isCurrent: isCurrent)
        .padding(.top, 26)

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, MemoraSpacing.xxl)
  }
}

private struct PageIndicator: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var current: OnboardingPage

  var body: some View {
    HStack(spacing: 7) {
      ForEach(OnboardingPage.allCases) { page in
        Capsule()
          .fill(page == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
          .frame(width: page == current ? 22 : 7, height: 7)
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.control, value: current)
    .accessibilityElement()
    .accessibilityLabel("ページ \((OnboardingPage.allCases.firstIndex(of: current) ?? 0) + 1) / \(OnboardingPage.allCases.count)")
  }
}
