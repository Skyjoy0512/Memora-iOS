import SwiftUI

enum AIQueryScope: Hashable {
  case file(UUID)
  case space(UUID)
  case global
}

struct AIQuestionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var selectedScope: AIQueryScope
  @State private var question: String
  @State private var submittedQuestion: String?
  @State private var answer: String?
  @State private var isAnswering = false

  init(scope: AIQueryScope, suggestedQuestion: String = "") {
    _selectedScope = State(initialValue: scope)
    _question = State(initialValue: suggestedQuestion)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 8) {
            Text("会議をまたいで、答えを探します")
              .font(.title2.bold())
            Text("回答には、元の会議と発言時刻を表示します。")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          if let submittedQuestion {
            VStack(alignment: .leading, spacing: 8) {
              Text("質問")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              Text(submittedQuestion)
                .font(.body.weight(.medium))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          }

          if isAnswering {
            HStack(spacing: 12) {
              ProgressView()
              Text("会議の中から根拠を探しています")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 14)
          } else if let answer {
            VStack(alignment: .leading, spacing: 18) {
              Label("回答", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.indigo)

              Text(answer)
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)

              VStack(alignment: .leading, spacing: 10) {
                Text("根拠")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)

                ForEach(sourceMeetings) { meeting in
                  NavigationLink {
                    TranscriptView(meetingID: meeting.id)
                  } label: {
                    HStack(spacing: 10) {
                      Image(systemName: "quote.bubble")
                        .foregroundStyle(.indigo)
                      VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title)
                          .font(.subheadline.weight(.semibold))
                          .foregroundStyle(.primary)
                        Text("00:42 の発言")
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }
                      Spacer()
                      Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                  }
                  .buttonStyle(.plain)
                  .accessibilityHint("根拠になった文字起こしを開きます")
                }
              }
            }
          } else {
            VStack(alignment: .leading, spacing: 12) {
              Text("たとえば")
                .font(.headline)
              SuggestionButton(title: "まだ決まっていないことは？") {
                question = "まだ決まっていないことは？"
              }
              SuggestionButton(title: "田中さんのタスクを教えて") {
                question = "田中さんのタスクを教えて"
              }
              SuggestionButton(title: "先週の会議を3行でまとめて") {
                question = "先週の会議を3行でまとめて"
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .padding(.bottom, 100)
      }
      .safeAreaInset(edge: .bottom) {
        composer
      }
      .navigationTitle("Memoraに聞く")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Picker("検索範囲", selection: $selectedScope) {
            ForEach(scopeOptions, id: \.self) { scope in
              Text(label(for: scope)).tag(scope)
            }
          }
          .pickerStyle(.menu)
        }
      }
    }
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField("会議について質問", text: $question, axis: .vertical)
        .lineLimit(1...4)
        .textFieldStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

      Button("送信", systemImage: "arrow.up") {
        ask()
      }
      .labelStyle(.iconOnly)
      .font(.headline)
      .frame(width: 44, height: 44)
      .foregroundStyle(.white)
      .background(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.indigo), in: Circle())
      .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnswering)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.regularMaterial)
  }

  private var scopeOptions: [AIQueryScope] {
    switch selectedScope {
    case .file(let meetingID):
      var scopes: [AIQueryScope] = [.file(meetingID)]
      if let spaceID = model.meeting(id: meetingID)?.spaceID {
        scopes.append(.space(spaceID))
      }
      scopes.append(.global)
      return scopes
    case .space(let spaceID):
      return [.space(spaceID), .global]
    case .global:
      return [.global] + model.spaces.prefix(2).map { .space($0.id) }
    }
  }

  private var sourceMeetings: [Meeting] {
    switch selectedScope {
    case .file(let id):
      return model.meeting(id: id).map { [$0] } ?? []
    case .space(let id):
      return Array(model.meetings.filter { $0.spaceID == id }.prefix(2))
    case .global:
      return Array(model.meetings.prefix(2))
    }
  }

  private func label(for scope: AIQueryScope) -> String {
    switch scope {
    case .file(let id):
      return model.meeting(id: id)?.title ?? "この会議"
    case .space(let id):
      return model.space(id: id)?.name ?? "このスペース"
    case .global:
      return "すべての会話"
    }
  }

  private func ask() {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    submittedQuestion = trimmed
    answer = nil
    isAnswering = true

    Task {
      try? await Task.sleep(for: .milliseconds(850))
      let generatedAnswer = "次に行うことは、初回録音フローの仕様確定と、Acme社へセキュリティ資料を送ることです。録音開始の速さを優先し、データは既定で端末内に保存する方針が確認されています。"
      answer = generatedAnswer
      isAnswering = false
      model.saveAIExchange(question: trimmed, answer: generatedAnswer, scopeLabel: label(for: selectedScope))
    }
  }
}

private struct SuggestionButton: View {
  var title: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        Text(title)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
        Spacer()
        Image(systemName: "arrow.up.left")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 10)
    }
    .buttonStyle(.plain)
  }
}
