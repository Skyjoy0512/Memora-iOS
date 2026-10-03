import SwiftUI

/// Words gathered from the person's mail, to add to the glossary with a tap.
/// Likely ones start checked; nothing is added until the person confirms.
struct GlossaryMailSuggestionsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var candidates: [GlossaryCandidate]?
  @State private var selected: Set<String> = []
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Group {
        if let candidates {
          if candidates.isEmpty {
            ContentUnavailableView(
              "新しい候補はありません",
              icon: .characterBookClosed,
              description: Text("よく出てくる名前や用語は、すでに登録されています。")
            )
          } else {
            list(candidates)
          }
        } else if let errorMessage {
          ContentUnavailableView {
            Label("メールを読めませんでした", icon: .exclamationmarkTriangle)
          } description: {
            Text(errorMessage)
          } actions: {
            Button("もう一度") { Task { await load() } }
          }
        } else {
          VStack(spacing: 12) {
            ProgressView()
            Text("最近のメールから候補を集めています…")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .navigationTitle("メールから追加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("\(selected.count)件を追加") {
            model.addGlossaryTerms((candidates ?? []).map(\.term).filter(selected.contains))
            dismiss()
          }
          .disabled(selected.isEmpty)
        }
      }
      .task { await load() }
    }
  }

  private func list(_ candidates: [GlossaryCandidate]) -> some View {
    List {
      Section {
        ForEach(candidates) { candidate in
          Button {
            if selected.contains(candidate.term) {
              selected.remove(candidate.term)
            } else {
              selected.insert(candidate.term)
            }
          } label: {
            HStack(spacing: 12) {
              Image(icon: selected.contains(candidate.term) ? .checkmarkCircleFill : .circle)
                .foregroundStyle(selected.contains(candidate.term) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .font(.title3)
              VStack(alignment: .leading, spacing: 2) {
                Text(candidate.term)
                  .foregroundStyle(.primary)
                Text("\(candidate.kind.rawValue) · \(candidate.count)件のメール")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selected.contains(candidate.term) ? .isSelected : [])
        }
      } footer: {
        Text("最近送ったメールの宛先と、送受信したメールの件名・冒頭から集めました。端末内で調べ、AIには送っていません。")
      }
    }
  }

  private func load() async {
    errorMessage = nil
    do {
      let found = try await model.glossaryCandidatesFromMail()
      candidates = found
      // People written to and companies are likely right; terms need a look.
      selected = Set(found.filter { $0.kind != .term || $0.count >= 3 }.map(\.term))
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
