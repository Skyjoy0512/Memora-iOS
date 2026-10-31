import SwiftUI

struct CommunityPostDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var post: CommunityPost
  @State private var isWorking = false
  @State private var showsAccount = false
  @State private var showsReport = false
  @State private var confirmsRemoval = false
  @State private var message: String?
  @State private var pendingVersion: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text(post.title).font(.largeTitle.weight(.semibold))
        Text(post.authorName).font(.subheadline).foregroundStyle(.secondary)
        Text(post.summary).font(.body)
        HStack(spacing: 24) {
          Button {
            authenticated {
              post = try await CommunityMarketplace.shared.like(post)
            }
          } label: { Label("\(post.liked == true ? "いいね済み" : "いいね") \(post.likes)", icon: .starFill).frame(minHeight: 44) }
            .accessibilityAddTraits(post.liked == true ? .isSelected : [])
          Label("追加 \(post.downloads)", icon: .squareAndArrowDown).font(.subheadline)
        }
        if post.status != "published" { Text(post.statusLabel).font(.headline) }
        MarketplaceDefinitionContent(definition: post.definition)
        if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
      }
      .padding(20).frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading).frame(maxWidth: .infinity)
    }
    .disabled(isWorking)
    .navigationTitle("コミュニティ").navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      Button {
        authenticated { try await install() }
      } label: {
        Text(pendingVersion != nil ? "集計を再試行" : model.hasCommunityItem(post) ? "追加済み" : "追加する")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(MemoraButtonStyle())
      .disabled(isWorking || post.status != "published" || (model.hasCommunityItem(post) && pendingVersion == nil))
      .padding(20).background(.bar)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          ShareLink(item: post.definition.shareText) { Label("内容を共有", icon: .squareAndArrowUp) }
          Button("投稿を報告", icon: .flag) { showsReport = true }
          Button("この投稿者を非表示", icon: .person) { CommunityMarketplace.shared.block(post.authorID); dismiss() }
          if FirebaseCommunitySession.shared.userID == post.authorID {
            Button("投稿を取り下げる", icon: .trash, role: .destructive) { confirmsRemoval = true }
          }
        } label: { Image(icon: .ellipsis, size: 20).accessibilityLabel("投稿の操作") }
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
