import SwiftUI

/// Suggests a project for a record that is in none: the strongest match with
/// why, a signal meter counted from that evidence, the other candidates in a
/// drawer, and a button that files it.
struct ProjectSuggestionCard: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var meeting: Meeting
  var suggestions: [ProjectSuggestion]

  @State private var selected = 0
  @State private var isDrawerOpen = false

  var body: some View {
    let active = suggestions[min(selected, suggestions.count - 1)]

    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text("「\(active.space.name)」に入れますか？")
          .font(.subheadline.weight(.semibold))
          .contentTransition(.opacity)
        ForEach(active.reasons, id: \.self) { reason in
          Text(reason)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .padding(16)
      .id(active.id)
      .transition(.opacity)

      if isDrawerOpen {
        VStack(alignment: .leading, spacing: 2) {
          Text("ほかの候補")
            .font(.caption.weight(.medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
          ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
            if index != selected {
              Button {
                selected = index
                isDrawerOpen = false
              } label: {
                HStack(spacing: 10) {
                  SignalMeter(signal: suggestion.signal)
                  Text(suggestion.space.name)
                    .font(.subheadline)
                    .lineLimit(1)
                  Spacer(minLength: 8)
                  Text(suggestion.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
          Button {
            model.dismissProjectSuggestion(for: meeting.id)
          } label: {
            HStack(spacing: 10) {
              SignalMeter(signal: 0)
              Text("どこにも入れない")
                .font(.subheadline)
              Spacer()
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        .padding(10)
        .overlay(alignment: .top) { Divider() }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }

      Divider()

      HStack(spacing: 10) {
        SignalMeter(signal: active.signal)
        Text(active.label)
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)
        Spacer()
        Button(isDrawerOpen ? "閉じる" : "ほかの候補") {
          isDrawerOpen.toggle()
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .buttonStyle(.plain)

        Button {
          model.setSpace(active.space.id, forMeeting: meeting.id)
        } label: {
          Text("入れる")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(Color.primary, in: Capsule())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }
    .memoraCard(radius: 18)
    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isDrawerOpen)
    .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: selected)
  }
}

/// Three bars, lit by how strong the evidence is.
private struct SignalMeter: View {
  var signal: Int

  var body: some View {
    HStack(alignment: .bottom, spacing: 2) {
      ForEach(0..<3, id: \.self) { bar in
        Capsule()
          .fill(bar < signal ? tone : Color.secondary.opacity(0.25))
          .frame(width: 4, height: 10)
      }
    }
    .accessibilityHidden(true)
  }

  private var tone: Color {
    signal >= 3 ? .green : signal >= 2 ? .orange : .secondary
  }
}
