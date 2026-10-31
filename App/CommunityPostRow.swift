import SwiftUI

struct CommunityPostRow: View {
  var post: CommunityPost
  var showsStatus = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(post.title).font(.headline)
      Text(post.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
      Text(post.authorName).font(.caption).foregroundStyle(.secondary)
      HStack(spacing: 18) {
        Label("\(post.likes)", icon: .starFill).accessibilityLabel("いいね\(post.likes)件")
        Label("\(post.downloads)", icon: .squareAndArrowDown).accessibilityLabel("追加\(post.downloads)件")
        if showsStatus { Text(post.statusLabel) }
      }.font(.caption).foregroundStyle(.secondary)
    }.padding(.vertical, 10)
  }
}
