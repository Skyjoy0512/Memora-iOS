import Foundation

struct ComposerDraftSnapshot {
  var question = ""
  var mentions: [ComposerMention] = []
  var attachment: AIAttachmentFileReference?
}
