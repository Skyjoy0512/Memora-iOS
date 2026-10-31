import Foundation
import Observation

@MainActor @Observable
final class CommunityMarketplace {
  static let shared = CommunityMarketplace()
  var posts: [CommunityPost] = []
  var nextCursor: String?
  var isLoading = false
  var failure: String?
  var sort = "popular"
  private let client = FirebaseMarketplaceClient()
  private var loadID = UUID()
  private(set) var blockedAuthors = UserDefaults.standard.stringArray(forKey: "memora.community.blockedAuthors") ?? []
  var isConfigured: Bool { FirebaseMarketplaceClient.isConfigured }

  func refresh(mine: Bool = false, more: Bool = false) async {
    guard isConfigured else { return }
    let requestID = UUID(); loadID = requestID
    isLoading = true; failure = nil
    defer { if loadID == requestID { isLoading = false } }
    do {
      var body: [String:Any] = ["action":mine ? "mine" : "list", "sort":sort]
      if more, let nextCursor { body["after"] = nextCursor }
      let result: Page = try await client.call(body, authenticated: mine || FirebaseCommunitySession.shared.isSignedIn)
      guard loadID == requestID else { return }
      let existing = more ? posts : []
      var seen = Set(existing.map(\.id))
      posts = existing + result.posts.filter { !blockedAuthors.contains($0.authorID) && seen.insert($0.id).inserted }
      nextCursor = result.nextCursor
    } catch { if loadID == requestID { failure = error.localizedDescription } }
  }

  func publish(_ definition: MarketplaceDefinition, authorName: String, requestID: UUID) async throws -> CommunityPost {
    let content = try definition.validated(allowedTools: Set(AgentTool.allCases.map(\.rawValue)))
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(content))
    let result: Published = try await client.call(["action":"publish","definition":object,
      "authorName":authorName,"requestID":requestID.uuidString,"acceptedTerms":"2026-10"])
    return result.post
  }

  func like(_ post: CommunityPost) async throws -> CommunityPost {
    let result: Like = try await client.call(["action":"like","postID":post.id,"liked":!(post.liked ?? false)])
    var updated = post; updated.likes = result.likes; updated.liked = result.liked
    if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index] = updated }
    return updated
  }

  func download(_ post: CommunityPost) async throws -> Download {
    try await client.call(["action":"download","postID":post.id])
  }

  func acknowledge(_ post: CommunityPost, version: String) async throws -> Int {
    let result: Install = try await client.call(["action":"installed","postID":post.id,"version":version])
    if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index].downloads = result.downloads }
    return result.downloads
  }

  func report(_ post: CommunityPost, reason: String) async throws {
    let _: Done = try await client.call(["action":"report","postID":post.id,"reason":reason])
  }

  func remove(_ post: CommunityPost) async throws {
    let _: Done = try await client.call(["action":"remove","postID":post.id])
    posts.removeAll { $0.id == post.id }
  }

  func block(_ authorID: String) {
    if !blockedAuthors.contains(authorID) { blockedAuthors.append(authorID) }
    UserDefaults.standard.set(blockedAuthors, forKey: "memora.community.blockedAuthors")
    posts.removeAll { $0.authorID == authorID }
  }
  func unblockAll() {
    blockedAuthors = []; UserDefaults.standard.removeObject(forKey: "memora.community.blockedAuthors")
  }

  struct Download: Decodable { var definition: MarketplaceDefinition; var version: String }
  private struct Page: Decodable { var posts: [CommunityPost]; var nextCursor: String? }
  private struct Published: Decodable { var post: CommunityPost }
  private struct Like: Decodable { var likes: Int; var liked: Bool }
  private struct Install: Decodable { var downloads: Int }
  private struct Done: Decodable { var ok: Bool }
}
