import SwiftUI

struct CommunityPostDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var post: CommunityPost
  var isMarketplaceSheet = false
  @State private var isWorking = false
  @State private var showsAccount = false
  @State private var showsReport = false
  @State private var confirmsRemoval = false
  @State private var message: String?
  @State private var pendingVersion: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let item {
          MarketplaceDetailHero(item: item, subtitle: "\(post.authorName) · \(post.definition.kind == .skill ? "スキル" : "要約テンプレート")") { EmptyView() }
        } else { Text(post.title).font(.largeTitle.weight(.semibold)) }
        if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
        MarketplaceDescription(text: post.summary)
        MarketplaceDetailFacts(fields: facts)
        HStack(spacing: 24) {
          Button {
            authenticated {
              post = try await CommunityMarketplace.shared.like(post)
            }
          } label: { Label("\(post.liked == true ? "いいね済み" : "いいね") \(post.likes)", icon: .starFill).frame(minHeight: 44) }
            .accessibilityAddTraits(post.liked == true ? .isSelected : [])
        }
        if post.status != "published" { Text(post.statusLabel).font(.headline) }
        postActions
        MarketplaceDefinitionContent(definition: post.definition)
      }
      .padding(20).frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading).frame(maxWidth: .infinity)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if item != nil {
        MarketplaceDetailFooter {
          Button { authenticated { try await install() } } label: {
            MarketplaceDetailActionLabel(title: isWorking ? "処理中…" : installTitle,
              icon: model.hasCommunityItem(post) && pendingVersion == nil ? .checkmark : nil)
          }
          .disabled(cannotInstall)
        }
      }
    }
    .disabled(isWorking)
    .background(MemoraPalette.background)
    .tint(MemoraPalette.textPrimary)
    .navigationTitle(post.title).navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(isMarketplaceSheet)
    .toolbar {
      if isMarketplaceSheet {
        ToolbarActionItem(placement: .topBarLeading) { ToolbarIconButton("閉じる", icon: .chevronLeft) { dismiss() } }
      }
      ToolbarActionItem(usesSystemBackground: true) {
        ShareLink(item: post.definition.shareText) {
          ToolbarActionLabel("内容を共有", icon: .squareAndArrowUp)
        }
      }
    }
    .sheet(isPresented: $showsAccount) { CommunityAccountView() }
    .confirmationDialog("投稿を報告", isPresented: $showsReport, titleVisibility: .visible) {
      Button("スパム") { report("spam") }
      Button("不適切・危険な内容") { report("unsafe") }
      Button("権利の侵害") { report("rights") }
      Button("その他") { report("other") }
    }
    .confirmationDialog("投稿を取り下げますか？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
      Button("取り下げる", role: .destructive) {
        authenticated { try await CommunityMarketplace.shared.remove(post); dismiss() }
      }
    }
  }

  private var postActions: some View {
    Menu {
      ShareLink(item: post.definition.shareText) { Label("内容を共有", icon: .squareAndArrowUp) }
      Button("投稿を報告", icon: .flag) { showsReport = true }
      Button("この投稿者を非表示", icon: .person) { CommunityMarketplace.shared.block(post.authorID); dismiss() }
      if FirebaseCommunitySession.shared.userID == post.authorID {
        Button("投稿を取り下げる", icon: .trash, role: .destructive) { confirmsRemoval = true }
      }
    } label: {
      Label("投稿の操作", icon: .ellipsis)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }
  }

  private var item: MarketplaceItem? {
    switch post.definition.kind {
    case .skill: post.definition.skill.map(MarketplaceItem.skill)
    case .template: post.definition.template.map(MarketplaceItem.template)
    }
  }

  private var installTitle: String {
    pendingVersion != nil ? "集計を再試行" : model.hasCommunityItem(post) ? "追加済み" : "追加する"
  }

  private var cannotInstall: Bool {
    isWorking || post.status != "published" || (model.hasCommunityItem(post) && pendingVersion == nil)
  }

  private var facts: [(String, String)] {
    var values = [("追加数", post.downloads.formatted()), ("カテゴリー", item?.category ?? "コミュニティ")]
    if let version = post.definition.skill?.version { values.append(("バージョン", String(version))) }
    values.append(("投稿日", Date(timeIntervalSince1970: post.createdAt / 1000)
      .formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(Locale(identifier: "ja_JP")))))
    values.append(("投稿者", post.authorName))
    return values
  }

  private func report(_ reason: String) {
    authenticated { try await CommunityMarketplace.shared.report(post, reason: reason); message = "報告を受け付けました。" }
  }

  private func authenticated(_ operation: @escaping @MainActor () async throws -> Void) {
    guard !isWorking else { return }
    guard FirebaseCommunitySession.shared.isSignedIn else { showsAccount = true; return }
    isWorking = true; message = nil
    Task { @MainActor in
      defer { isWorking = false }
      do { try await operation() } catch { message = error.localizedDescription }
    }
  }

  private func install() async throws {
    if let pendingVersion {
      post.downloads = try await CommunityMarketplace.shared.acknowledge(post, version: pendingVersion)
      self.pendingVersion = nil
      return
    }
    guard let context = LocalImportContext(in: model) else { throw CommunityError.saveFailed }
    let value = try await CommunityMarketplace.shared.download(post)
    guard context.isCurrent(in: model) else { throw CommunityError.server("ワークスペースが変わりました。開き直してください。") }
    try model.installCommunityDefinition(value.definition, postID: post.id)
    pendingVersion = value.version
    do {
      post.downloads = try await CommunityMarketplace.shared.acknowledge(post, version: value.version)
      pendingVersion = nil
    } catch { message = "追加しました。集計の更新は再試行できます。" }
  }
}
