import SwiftUI

struct JournalSummaryView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .largeTitle) private var daySize = 104.0
  var date: Date
  @Binding var backdrops: JournalBackdropSelection
  @State private var showsReview = false
  @State private var showsCreate = false

  var body: some View {
    let recap = JournalDailyRecap.build(date: date, meetings: model.meetings,
      tasks: model.tasks, entries: model.lifeLogEntries)
    let shareText = ([date.formatted(date: .complete, time: .omitted), recap.heading,
      recap.narrative] + recap.highlights).joined(separator: "\n\n")

    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(alignment: .leading, spacing: 16) {
            Text(date.formatted(.dateTime.year().month().day().weekday(.wide)))
              .font(.subheadline.weight(.medium))
            Text(Calendar.current.component(.day, from: date).formatted())
              .font(.system(size: daySize, weight: .regular, design: .serif))
              .accessibilityHidden(true)
            Text(recap.heading)
              .font(.largeTitle.bold())
              .accessibilityAddTraits(.isHeader)
              .fixedSize(horizontal: false, vertical: true)
            Text(recap.narrative)
              .font(.body)
              .lineSpacing(8)
              .fixedSize(horizontal: false, vertical: true)
          }

          actionBar(shareText: shareText)
          .buttonBorderShape(.capsule)
          .controlSize(.large)

          divider

          if !recap.items.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
              Text(Calendar.current.isDateInToday(date) ? "今日のハイライト" : "この日のハイライト")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
              ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                  ForEach(recap.items.prefix(6)) { item in
                    highlight(item)
                      .frame(width: typeSize.isAccessibilitySize ? 300 : 220)
                  }
                }
                .scrollTargetLayout()
              }
              .scrollTargetBehavior(.viewAligned)
              .scrollIndicators(.hidden)
            }
            divider
          }

          VStack(alignment: .leading, spacing: 14) {
            Text("記録から振り返る")
              .font(.title2.bold())
              .accessibilityAddTraits(.isHeader)
            Text("記録と完了したタスクから、1日を振り返っています。気分や記録のない活動は推測しません。")
              .font(.subheadline)
              .lineSpacing(5)
            Button("日・週の振り返りを詳しく見る", icon: .chartBar) {
              InteractionFeedback.shared.send(.tap)
              showsReview = true
            }
            .frame(minHeight: 44)
            .buttonStyle(.bordered)
          }
          .padding(20)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(panelBackground, in: RoundedRectangle(cornerRadius: 24))

          Text("背景写真はイメージです · \(backdrops.current.label)")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 40)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
      .background { JournalBackdropView(backdrop: backdrops.current, immersive: true).ignoresSafeArea() }
      .foregroundStyle(.white)
      .tint(.white)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("ジャーナルに戻る", icon: .chevronLeft) { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("背景を変更", icon: .arrowClockwise) {
              backdrops.shuffle(date)
              InteractionFeedback.shared.send(.selection)
            }
            Button("詳しい振り返り", icon: .chartBar) {
              InteractionFeedback.shared.send(.tap)
              showsReview = true
            }
          } label: {
            Label("その他", icon: .ellipsis).labelStyle(.iconOnly)
          }
        }
      }
      .sheet(isPresented: $showsReview) { JournalReviewView(date: date) }
      .sheet(isPresented: $showsCreate) { LifeLogCreationSheet(date: Calendar.current.isDateInToday(date) ? .now : date) }
    }
    .preferredColorScheme(.dark)
  }

  @ViewBuilder private func actionBar(shareText: String) -> some View {
    if #available(iOS 26.0, *), !reduceTransparency {
      actionLayout(shareText: shareText).buttonStyle(.glass)
    } else {
      actionLayout(shareText: shareText).buttonStyle(.bordered)
    }
  }

  private func actionLayout(shareText: String) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) { actions(shareText: shareText) }
      VStack(alignment: .leading, spacing: 12) { actions(shareText: shareText) }
    }
  }

  @ViewBuilder private func actions(shareText: String) -> some View {
    ShareLink(item: shareText) { Label("共有", icon: .squareAndArrowUp) }
    Button("記録を追加", icon: .squareAndPencil) {
      InteractionFeedback.shared.send(.tap)
      showsCreate = true
    }
  }

  private var panelBackground: Color {
    reduceTransparency ? Color(white: 0.12) : .white.opacity(0.12)
  }

  private var divider: some View {
    HStack(spacing: 16) {
      Rectangle().frame(height: 1)
      Image(icon: .sparkles).font(.subheadline)
      Rectangle().frame(height: 1)
    }
    .foregroundStyle(.white.opacity(0.3))
    .accessibilityHidden(true)
  }

  private func highlight(_ item: JournalRecapHighlight) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(item.date.formatted(date: .omitted, time: .shortened), icon: item.icon)
        .font(.subheadline.weight(.medium))
      Text(item.title).font(.headline).lineLimit(3)
      Text(item.summary.isEmpty ? item.category : item.summary)
        .font(.subheadline)
        .lineSpacing(4)
        .lineLimit(4)
    }
    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    .padding(18)
    .background(panelBackground, in: RoundedRectangle(cornerRadius: 22))
    .overlay {
      RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.14), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}
