import SwiftUI

struct CommunityCatalogView: View {
  @State private var community = CommunityMarketplace.shared
  @State private var mine = false
  @State private var showsAccount = false
  @State private var selectedPost: CommunityPost?

  var body: some View {
    List {
      Section {
        Picker("表示", selection: $mine) { Text("みんなの投稿").tag(false); Text("自分の投稿").tag(true) }.pickerStyle(.segmented)
        if !mine {
          Picker("並べ替え", selection: $community.sort) { Text("人気順").tag("popular"); Text("新着順").tag("latest") }
        }
      }
      if !community.isConfigured {
        Section { ContentUnavailableView("コミュニティは準備中", icon: .person2, description: Text("公開サービスの接続後に利用できます。")) }
      } else {
        if let failure = community.failure {
          Section { Text(failure).font(.subheadline); Button("再読み込み") { Task { await community.refresh(mine: mine) } } }
        }
        ForEach(community.posts) { post in
          Button { selectedPost = post } label: { CommunityPostRow(post: post, showsStatus: mine) }
            .buttonStyle(.plain)
        }
        if community.posts.isEmpty && !community.isLoading && community.failure == nil {
          ContentUnavailableView(mine ? "投稿はまだありません" : "投稿をお待ちしています", icon: .person2)
        }
        if community.isLoading { ProgressView().frame(maxWidth: .infinity) }
        if community.nextCursor != nil && !community.isLoading {
          Button("もっと見る") { Task { await community.refresh(mine: mine, more: true) } }
        }
      }
    }
    .listStyle(.plain)
    .navigationTitle("コミュニティ").navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(placement: .topBarTrailing) { ToolbarIconButton("アカウント", icon: .person) { showsAccount = true } } }
    .task(id: "\(mine)-\(community.sort)") {
      community.posts = []; community.nextCursor = nil
      await community.refresh(mine: mine)
    }
    .onChange(of: FirebaseCommunitySession.shared.generation) { _, _ in
      community.posts = []; community.nextCursor = nil
    }
    .refreshable { await community.refresh(mine: mine) }
    .sheet(isPresented: $showsAccount, onDismiss: { Task { await community.refresh(mine: mine) } }) { CommunityAccountView() }
    .sheet(item: $selectedPost) { post in
      NavigationStack { CommunityPostDetailView(post: post, isMarketplaceSheet: true) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }
  }
}
