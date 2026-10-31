import SwiftUI

struct CommunityPublishSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var definition: MarketplaceDefinition
  @State private var authorName = ""
  @State private var acceptsTerms = false
  @State private var isWorking = false
  @State private var showsAccount = false
  @State private var message: String?
  @State private var published: CommunityPost?
  @State private var requestID = UUID()

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          Text(definition.title).font(.headline)
          Text(definition.summary).font(.subheadline).foregroundStyle(.secondary)
          DisclosureGroup("公開する内容") { MarketplaceDefinitionContent(definition: definition) }
        }
        if let published {
          Section { Label(published.statusLabel, icon: .checkmark) }
        } else {
          Section {
            TextField("投稿者名", text: $authorName).accessibilityLabel("公開する投稿者名")
            Toggle("公開ルールに同意", isOn: $acceptsTerms)
            DisclosureGroup("公開ルール") {
              Text("共有する権利のある手順・テンプレートだけを投稿してください。個人情報や秘密のキー、他者への攻撃を含めないでください。投稿者名と内容は審査後に公開されます。不適切な投稿は非表示・削除の対象となります。")
                .font(.subheadline)
            }
          }
          Section {
            if !FirebaseMarketplaceClient.isConfigured {
              Text(CommunityError.unconfigured.localizedDescription).font(.subheadline).foregroundStyle(.secondary)
            } else if !FirebaseCommunitySession.shared.isSignedIn {
              Button("ログインして投稿") { showsAccount = true }
            } else {
              Button("審査に送る") { publish() }
                .disabled(!acceptsTerms || authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authorName.count > 60)
            }
          }
        }
        if isWorking { ProgressView("送信中") }
        if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
      }
      .disabled(isWorking)
      .navigationTitle("コミュニティに投稿").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { ToolbarIconButton(published == nil ? "閉じる" : "完了", icon: .xmark) { dismiss() } } }
      .interactiveDismissDisabled(isWorking)
      .onAppear { if authorName.isEmpty { authorName = model.profile.name } }
      .sheet(isPresented: $showsAccount) { CommunityAccountView() }
    }
  }

  private func publish() {
    guard !isWorking else { return }; isWorking = true; message = nil
    Task { @MainActor in
      defer { isWorking = false }
      do { published = try await CommunityMarketplace.shared.publish(definition, authorName: authorName, requestID: requestID) }
      catch { message = error.localizedDescription }
    }
  }
}
