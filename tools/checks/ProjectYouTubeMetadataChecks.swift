import Foundation

@main
struct ProjectYouTubeMetadataChecks {
  static func main() throws {
    let url = URL(string: "https://youtu.be/dQw4w9WgXcQ?si=tracking")!
    let request = try ProjectYouTubeMetadata.request(for: url)
    precondition(request.url?.host == "www.youtube.com" && request.url?.path == "/oembed")
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
    precondition(components.queryItems?.first { $0.name == "url" }?.value == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    for bad in ["https://example.com", "https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ", "https://127.0.0.1"] {
      do { _ = try ProjectYouTubeMetadata.request(for: URL(string: bad)!); preconditionFailure("untrusted endpoint") } catch {}
    }
    let fixture = Data(#"{"type":"video","provider_name":"YouTube","title":"  箱根旅行  ","author_name":"作者"}"#.utf8)
    let value = try ProjectYouTubeMetadata.decode(fixture)
    precondition(value.title == "箱根旅行" && value.author == "作者")
    for bad in [Data(#"{"type":"link","provider_name":"YouTube","title":"偽"}"#.utf8), Data(repeating: 0, count: 65_537)] {
      do { _ = try ProjectYouTubeMetadata.decode(bad); preconditionFailure("invalid metadata") } catch {}
    }
    print("ProjectYouTubeMetadataChecks: passed (fixed endpoint, canonical ID, response validation, size limit)")
  }
}
