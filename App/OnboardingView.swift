import SwiftUI

struct OnboardingView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var startRecording: @MainActor () async -> Void
  var showSample: () -> Void
  var skip: () -> Void
  @State private var page = OnboardingPage.record
  @State private var isOccupationSelectionPresented = false
  @State private var isStartingRecording = false

  var body: some View {
    VStack(spacing: 0) {
      header
      GeometryReader { geometry in
        ScrollView {
          VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
            introduction
            if dynamicTypeSize.isAccessibilitySize { footer }
          }
          .padding(.vertical, MemoraSpacing.xxl)
          .frame(minHeight: geometry.size.height, alignment: .center)
          .padding(.horizontal, MemoraSpacing.screen)
          .frame(maxWidth: MemoraSpacing.readingWidth)
          .frame(maxWidth: .infinity, alignment: .center)
        }
        .id(page)
      }
      if !dynamicTypeSize.isAccessibilitySize {
        footer
          .padding(.horizontal, MemoraSpacing.screen)
          .padding(.bottom, MemoraSpacing.sm)
          .frame(maxWidth: MemoraSpacing.readingWidth)
      }
    }
    .background(MemoraPalette.background)
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

  private var header: some View {
    ZStack {
      MemoraWordmark(width: 84)
        .accessibilityLabel("Memora")
      HStack(spacing: MemoraSpacing.sm) {
        if let previous = page.previous {
          Button {
            page = previous
          } label: {
            Label("前へ", icon: .chevronLeft)
              .labelStyle(.iconOnly)
              .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(isStartingRecording)
        }
        Spacer()
        if page.next != nil {
          Button("スキップ", action: skip)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minHeight: MemoraSpacing.touchTarget)
            .accessibilityIdentifier("onboarding.skip")
        }
      }
    }
    .frame(minHeight: MemoraSpacing.touchTarget)
    .padding(.horizontal, MemoraSpacing.screen)
  }

  private var introduction: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
      VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
        Text("\(page.number) / \(OnboardingPage.allCases.count)")
          .font(.footnote.monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityLabel("ページ \(page.number) / \(OnboardingPage.allCases.count)")
        Text(page.title)
          .font(MemoraTypography.display)
          .accessibilityAddTraits(.isHeader)
        Text(page.detail)
          .font(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      OnboardingPreview(page: page)
      if page == .understand {
        aiDetails
      }
      if page == .act {
        Button("仕事・活動を選ぶ（任意）") { isOccupationSelectionPresented = true }
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(minHeight: MemoraSpacing.touchTarget)
          .disabled(isStartingRecording)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var footer: some View {
    Group {
      if let next = page.next {
        Button {
          page = next
        } label: {
          Text("次へ").frame(maxWidth: .infinity)
        }
        .buttonStyle(MemoraButtonStyle())
        .accessibilityIdentifier("onboarding.next")
      } else {
        actions
      }
    }
  }

  private var aiDetails: some View {
    DisclosureGroup {
      Text("文字起こしには対応言語のモデル、要約には対応端末のAIかクラウドAIの設定が必要です。初回のモデル取得や処理に時間がかかる場合があります。クラウドAIには、許可した内容だけを送信します。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.vertical, MemoraSpacing.sm)
    } label: {
      Text("文字起こしとAIについて")
        .font(.subheadline)
        .frame(minHeight: MemoraSpacing.touchTarget)
    }
  }

  private var actions: some View {
    VStack(spacing: MemoraSpacing.sm) {
      Text("録音はこのiPhoneに保存されます。開始時にマイクの許可を確認します。")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        isStartingRecording = true
        Task {
          await startRecording()
          isStartingRecording = false
        }
      } label: {
        Text(isStartingRecording ? "録音を準備中…" : "録音してみる")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(MemoraButtonStyle())
      .accessibilityIdentifier("onboarding.primary")
      .accessibilityHint("マイクの許可を確認してから録音します。")

      let optionsLayout = dynamicTypeSize >= .xxLarge
        ? AnyLayout(VStackLayout(spacing: 0))
        : AnyLayout(HStackLayout(spacing: MemoraSpacing.md))
      optionsLayout {
        Button("サンプルを見る", action: showSample)
          .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget)
          .accessibilityIdentifier("onboarding.sample")
        Button("このiPhoneで始める", action: skip)
          .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget)
          .accessibilityIdentifier("onboarding.local")
      }
      .font(.subheadline)
      .multilineTextAlignment(.center)
      .foregroundStyle(.secondary)
    }
    .disabled(isStartingRecording)
  }
}
