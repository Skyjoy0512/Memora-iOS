import SwiftUI

struct OnboardingView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var startRecording: @MainActor () async -> Void
  var showSample: () -> Void
  var skip: () -> Void
  @State private var page = OnboardingPage.record
  @State private var isOccupationSelectionPresented = false
  @State private var isStartingRecording = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        HStack(spacing: MemoraSpacing.sm) {
          MemoraBrandMark(width: 96).accessibilityHidden(true)
          MemoraWordmark(width: 96).accessibilityHidden(true)
        }
        Spacer()
        if page.next != nil {
          Button("スキップ", action: skip)
            .font(.subheadline)
            .frame(minWidth: MemoraSpacing.touchTarget, minHeight: MemoraSpacing.touchTarget)
            .accessibilityIdentifier("onboarding.skip")
        }
      }
      .frame(minHeight: MemoraSpacing.touchTarget)
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
              OnboardingPreview(page: page)
              if page == .understand {
                aiDetails
              }
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
                  .disabled(isStartingRecording)
              }
            }

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
              Button("仕事・活動を選ぶ（任意）") { isOccupationSelectionPresented = true }
                .font(.subheadline)
                .frame(minHeight: MemoraSpacing.touchTarget)
                .disabled(isStartingRecording)
            }
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
    VStack(spacing: MemoraSpacing.md) {
      Text("録音はこのiPhoneに保存されます。マイクの許可は録音を始めるときに確認します。")
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

      Button(action: showSample) {
        Text("サンプルを見る").frame(maxWidth: .infinity)
      }
        .buttonStyle(MemoraButtonStyle(emphasis: .secondary))
        .accessibilityIdentifier("onboarding.sample")
      Button("このiPhoneで始める", action: skip)
        .font(.subheadline)
        .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget)
        .accessibilityIdentifier("onboarding.local")
    }
    .disabled(isStartingRecording)
  }
}
