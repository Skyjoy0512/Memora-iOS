import SwiftUI

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
        HStack(spacing: MemoraSpacing.sm) {
          MemoraBrandMark(width: 96).accessibilityHidden(true)
          MemoraWordmark(width: 96).accessibilityHidden(true)
        }
        Spacer()
        Button("スキップ", action: skip)
          .font(.subheadline)
          .frame(minWidth: MemoraSpacing.touchTarget, minHeight: MemoraSpacing.touchTarget)
          .accessibilityIdentifier("onboarding.skip")
      }
      .padding(.horizontal, MemoraSpacing.screen)

      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: MemoraSpacing.section) {
            VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
              Text(page.title)
                .font(MemoraTypography.display)
                .accessibilityAddTraits(.isHeader)
              Text(page.detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
              OnboardingPreview(page: page, isCurrent: true)
            }
            .id(page)

            HStack {
              Text("\((OnboardingPage.allCases.firstIndex(of: page) ?? 0) + 1) / \(OnboardingPage.allCases.count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("ページ \((OnboardingPage.allCases.firstIndex(of: page) ?? 0) + 1) / \(OnboardingPage.allCases.count)")
              Spacer()
              if page != .record {
                Button("前へ") { page = page == .act ? .understand : .record }
                  .frame(minWidth: MemoraSpacing.touchTarget, minHeight: MemoraSpacing.touchTarget)
              }
              if let next = page.next {
                Button("次へ") { page = next }
                  .frame(minWidth: MemoraSpacing.touchTarget, minHeight: MemoraSpacing.touchTarget)
                  .accessibilityLabel("説明の次のページ")
                  .accessibilityIdentifier("onboarding.next")
              }
            }
            actions

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
            if page == .act {
              Button("仕事・活動を選ぶ（任意）") { isOccupationSelectionPresented = true }
                .font(.subheadline)
                .frame(minHeight: MemoraSpacing.touchTarget)
            }
            Text("録音はまず、このiPhoneに保存されます。ログインや購入は必要ありません。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, MemoraSpacing.screen)
          .padding(.vertical, MemoraSpacing.xxl)
          .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
          .frame(maxWidth: .infinity)
        }
        .onChange(of: page) { proxy.scrollTo(page, anchor: .top) }
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

  private var actions: some View {
    VStack(spacing: MemoraSpacing.md) {
      Button {
        startRecording()
      } label: {
        Text("録音してみる")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(MemoraButtonStyle())
      .accessibilityIdentifier("onboarding.primary")
      .accessibilityHint("マイクの許可を確認してから録音します。")

      Button(action: showSample) {
        Text("サンプルを見る").frame(maxWidth: .infinity)
      }
        .buttonStyle(MemoraButtonStyle(emphasis: .secondary))
        .accessibilityIdentifier("onboarding.sample")
      Button("ログインせず始める", action: skip)
        .font(.subheadline)
        .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget)
        .accessibilityIdentifier("onboarding.local")
    }
  }
}
