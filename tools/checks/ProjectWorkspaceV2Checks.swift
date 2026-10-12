import Foundation

@main
struct ProjectWorkspaceV2Checks {
  static func main() throws {
    let video = "dQw4w9WgXcQ"
    let variants = [
      "https://youtu.be/\(video)?si=tracking",
      "https://m.youtube.com/watch?v=\(video)&utm_source=share",
      "https://www.youtube.com/shorts/\(video)",
      "https://youtube.com/embed/\(video)"
    ]
    let links = try variants.map(ProjectSourceURL.normalized)
    precondition(Set(links.map(\.url)).count == 1)
    precondition(links.allSatisfy { $0.kind == .youtube && $0.youtubeID == video })
    let web = try ProjectSourceURL.normalized("  https://EXAMPLE.com:443/article?b=2&utm_source=x&a=1#part  ")
    precondition(web.url.absoluteString == "https://example.com/article?a=1&b=2")
    for input in ["file:///etc/passwd", "javascript:alert(1)", "http://example.com", "https://user:pass@example.com",
                  "https://localhost", "https://service.local", "https://127.0.0.1", "https://[::1]",
                  "https://2130706433", "https://0x7f000001", "https://127.1", "https://example.com:8443",
                  "https://youtube.com/watch?v=bad", "https://youtu.be/"] {
      do { _ = try ProjectSourceURL.normalized(input); preconditionFailure("Accepted unsafe link") }
      catch is ProjectSourceURL.InvalidLink {}
    }
    let projectID = UUID()
    let source = ProjectSource(projectID: projectID, kind: .web, title: "記事", originalURL: web.url)
    let decoded = try JSONDecoder().decode(ProjectSource.self, from: JSONEncoder().encode(source))
    precondition(decoded == source && !decoded.canProvideText)
    precondition(!RecordAccessPolicy.allows(decoded.privacy, purpose: .cloudAI))
    var ready = source
    ready.processingStatus = .ready
    ready.extractedTextReference = "evidence.txt"
    precondition(ready.canProvideText)
    let citation = ProjectCitation(target: .source(source.id), title: source.title, excerpt: "実際の本文", page: 2)
    let answer = ProjectChatTurn(role: .assistant, text: "回答", citations: [citation])
    let thread = ProjectChatThread(projectID: projectID, title: "旅行", messages: [answer])
    let restored = try JSONDecoder().decode(ProjectChatThread.self, from: JSONEncoder().encode(thread))
    precondition(restored == thread && restored.projectID == projectID)
    var detached = thread
    detached.projectID = nil
    precondition(detached.messages == thread.messages && detached.id == thread.id)
    print("ProjectWorkspaceV2Checks: passed (URL normalization, YouTube deduplication, unsafe links, source/privacy/thread/citation codecs)")
  }
}
