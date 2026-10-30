import SwiftUI

struct PresentationEditorView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var document: MemoraDocument
  @State private var slidePath: [UUID]
  @State private var didLoadDraft = false
  @State private var draft: MemoraDocument
  @State private var failure: String?
  @State private var confirmsDiscard = false

  init(document: MemoraDocument, initialSlideID: UUID? = nil) {
    _slidePath = State(initialValue: initialSlideID.map { [$0] } ?? [])
    self.document = document
    _draft = State(initialValue: document)
  }

  var body: some View {
    NavigationStack(path: $slidePath) {
      List {
        Section("資料名") { TextField("資料名", text: $draft.title) }
        Section {
          if let binding = Binding($draft.presentationPlan) {
            NavigationLink("目的と構成") { PresentationPlanFields(plan: binding, slides: draft.slides) }
          } else {
            Button("目的と構成を整理") {
              draft.presentationPlan = PresentationPlan(storyline: draft.slides.map {
                .init(slideID: $0.id, claim: $0.title.isEmpty ? "主張を入力" : $0.title)
              })
            }
          }
        }
        if document.companyTemplateID == nil {
          Section {
            NavigationLink("AIで一部を修正") {
              PresentationRevisionView(draft: $draft, original: document)
            }
          }
        }
        if document.companyTemplateID != nil {
          Section {
            Text("原本と以前のファイルを保持します。対応する追加方式の資料は、保存後に資料画面で会社PPTXへ書き出せます。")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
        Section {
          ForEach($draft.slides) { $slide in
            NavigationLink(value: slide.id) {
              VStack(alignment: .leading, spacing: 8) {
                Text(slide.title.isEmpty ? "無題のスライド" : slide.title).font(.headline)
                Text(slide.composition?.layout.title ?? "従来のスライド")
                  .font(.caption).foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .contextMenu {
              Button("複製", icon: .docOnDoc) { duplicate(slide.id) }
              Button("削除", icon: .trash, role: .destructive) { draft.slides.removeAll { $0.id == slide.id } }
            }
          }
          .onDelete { draft.slides.remove(atOffsets: $0) }
          .onMove { draft.slides.move(fromOffsets: $0, toOffset: $1) }
          Button("スライドを追加", icon: .plus) {
            draft.slides.append(DocumentSlide(title: "", bullets: [], composition: .init(layout: .b01)))
          }
          .disabled(draft.slides.count >= 65)
        } header: { Text("スライド（\(draft.slides.count)枚）") }
        Section {
          Text("各スライドを開いて内容を修正できます。並べ替え・削除は編集ボタンから行えます。図表はPPTXで編集可能な図形になります。出典・論理・最終描画は書き出し前に確認してください。")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .navigationDestination(for: UUID.self) { id in
        if let index = draft.slides.firstIndex(where: { $0.id == id }) {
          PresentationSlideEditor(slide: $draft.slides[index])
        } else { Text("このスライドは削除されています。") }
      }
      .navigationTitle("スライドを編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) {
            if draft == document { dismiss() } else { confirmsDiscard = true }
          }
        }
        ToolbarItem(placement: .primaryAction) { EditButton() }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark, action: save)
            .disabled(draft.slides.isEmpty)
        }
      }
      .task {
        guard !didLoadDraft else { return }
        didLoadDraft = true
        if let json = DraftStore.load(draftKey), let data = json.data(using: .utf8),
           let restored = try? JSONDecoder().decode(MemoraDocument.self, from: data),
           restored.id == document.id, restored.updatedAt == document.updatedAt { draft = restored }
      }
      .onChange(of: draft) { _, value in
        if let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) {
          DraftStore.save(json, key: draftKey)
        }
      }
      .interactiveDismissDisabled(draft != document)
      .confirmationDialog("変更は下書きに残して閉じますか？", isPresented: $confirmsDiscard, titleVisibility: .visible) {
        Button("下書きを残して閉じる") { dismiss() }
        Button("下書きを破棄", role: .destructive) { DraftStore.clear(draftKey); dismiss() }
      }
      .alert("保存できませんでした", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
        Button("閉じる", role: .cancel) {}
      } message: { Text(failure ?? "") }
    }
  }

  private var draftKey: String { "presentation.\(document.id).\(document.updatedAt.timeIntervalSince1970)" }

  private func save() {
    guard model.updateDocumentSlides(document.id, title: draft.title, slides: draft.slides, expectedUpdatedAt: document.updatedAt,
                                    plan: draft.presentationPlan) else {
      failure = "資料が別の画面で変更されたか、保存先に書き込めません。入力内容は下書きに残っています。"
      return
    }
    DraftStore.clear(draftKey); dismiss()
  }

  private func duplicate(_ id: UUID) {
    guard draft.slides.count < 65, let index = draft.slides.firstIndex(where: { $0.id == id }) else { return }
    var copy = draft.slides[index]; copy.id = UUID()
    draft.slides.insert(copy, at: index + 1)
  }
}
