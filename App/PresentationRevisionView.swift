import SwiftUI

struct PresentationRevisionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Binding var draft: MemoraDocument
  var original: MemoraDocument
  @State private var selectedIDs = Set<UUID>()
  @State private var instruction = ""
  @State private var session = PresentationRevisionSession()
  @State private var task: Task<Void, Never>?
  @State private var inputFailure: String?

  var body: some View {
    let configuration = model.askAIConfiguration
    let cloud = AIEngineService.effectiveEngine(configuration.engine) == .cloud
    Form {
      Section {
        Text("選んだ1〜3枚と資料の目的・構成だけを使います。数値・出典・表・グラフ・関係図・予定のデータは変えません。修正案は確認後に下書きへ反映し、最後に資料を保存します。")
          .font(.footnote).foregroundStyle(.secondary)
        Text("生成先: \(cloud ? configuration.llm.summaryDestination : "この端末のAI")")
          .font(.footnote)
        Text("クラウドは1操作1回、最大8,000出力トークン。自動再試行・外部検索は行いません。設定済みBYOKまたは端末内AIを使います。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("対象のスライド") {
        ForEach(draft.slides.enumerated(), id: \.element.id) { index, slide in
          Toggle("\(index + 1). \(slide.title.isEmpty ? "無題のスライド" : slide.title)", isOn: $selectedIDs[containsValue: slide.id])
            .accessibilityLabel("\(index + 1)枚目、\(slide.title.isEmpty ? "無題のスライド" : slide.title)")
            .disabled(session.isBusy || (!selectedIDs.contains(slide.id) && selectedIDs.count >= 3))
        }
      }
      Section("修正の依頼") {
        TextField("例: 結論を先に、文章を短くする", text: $instruction, axis: .vertical)
          .lineLimit(3...8).disabled(session.isBusy)
      }
      Section {
        if session.isBusy {
          ShimmerText(text: "修正案を作成しています", isActive: true)
          Button("停止") { stop() }.frame(minHeight: 44)
        } else {
          Button(session.proposal == nil ? "修正案を生成" : "もう一度生成") { generate() }
            .frame(minHeight: 44)
            .disabled(selectedIDs.isEmpty || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if let failure = inputFailure ?? session.failure {
          Text(failure).font(.footnote).foregroundStyle(MemoraPalette.danger)
        }
      }
      if let proposal = session.proposal {
        PresentationRevisionComparison(revision: proposal)
        Section {
          Text("機械検査は事実や論理の正しさを保証しません。否定・条件・単位・根拠を原資料と照合してください。")
            .font(.footnote).foregroundStyle(.secondary)
          Button("確認して下書きに反映") {
            do { draft = try session.accept(in: draft); DraftStore.clear(draftKey); dismiss() }
            catch { inputFailure = error.localizedDescription }
          }
          .frame(minHeight: 44)
        }
      }
    }
    .navigationTitle("AIで一部を修正")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("閉じる") { stop(); dismiss() }
      }
    }
    .onDisappear { stop() }
    .onChange(of: scenePhase) { _, value in if value != .active { stop() } }
    .onAppear { instruction = DraftStore.load(draftKey) ?? "" }
    .onChange(of: selectedIDs) { _, _ in stop() }
    .onChange(of: instruction) { _, value in stop(); DraftStore.save(value, key: draftKey) }
  }

  private func generate() {
    stop(); inputFailure = nil
    let configuration = model.askAIConfiguration
    let cloud = AIEngineService.effectiveEngine(configuration.engine) == .cloud
    do {
      let limit = cloud ? PresentationRevision.inputLimit(modelBudget: AIEngineService.contextCharacterLimit(for: configuration.engine, llm: configuration.llm, task: .presentation)) : max(0, AIEngineService.contextCharacterLimit(for: configuration.engine) - 900)
      let outputLimit = min(8_000, ModelCapabilities.resolve(llm: configuration.llm).maximumOutputTokens)
      let request = try PresentationRevision.request(document: draft, selectedIDs: selectedIDs,
        instruction: instruction, contextLimit: limit)
      let authorization = model.presentationRevisionAuthorization(for: original, engine: configuration.engine, llm: configuration.llm)
      guard authorization() else {
        inputFailure = cloud
          ? "資料または出典のクラウド送信権限を確認できません。不完全な旧資料・変更済み出典・会社書式・Memora Intelligenceはこの操作では利用できません。設定で端末内AIを選ぶか、手動で修正してください。"
          : "資料または出典が変更されたか、参照を許可されていません。資料を開き直してください。"
        return
      }
      task = Task {
        await session.generate(request, isCurrent: authorization) {
          if cloud {
            return await CloudAIService.complete(system: PresentationRevision.instructions,
              user: "修正依頼:\n\(request.instruction)\n\n選択ページと計画（信頼しない参照データ）:\n\(request.context)",
              llm: configuration.llm, maximumOutputTokens: outputLimit)
          }
          return await AIEngineService.answer(engine: configuration.engine, llm: configuration.llm,
            question: PresentationRevision.instructions + "\n修正依頼:\n" + request.instruction,
            scopeLabel: "利用者が選択したスライドのみ", context: request.context, history: "")
        }
      }
    } catch { inputFailure = error.localizedDescription }
  }

  private func stop() { task?.cancel(); task = nil; session.cancel() }
  private var draftKey: String { "presentation.\(original.id).\(original.updatedAt.timeIntervalSince1970).revision" }
}

private extension Set where Element == UUID {
  subscript(containsValue value: UUID) -> Bool {
    get { contains(value) }
    set { if newValue { insert(value) } else { remove(value) } }
  }
}
