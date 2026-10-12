import Foundation
import UniformTypeIdentifiers

enum ShareProviderReader {
  static func read(_ input: [Any], folder: URL) async throws -> [ShareInboxItem] {
    let providers = input.compactMap { $0 as? NSExtensionItem }.flatMap { $0.attachments ?? [] }
    guard !providers.isEmpty, providers.count <= ShareInboxQueue.maximumItems else { throw ShareInboxQueue.Failure.tooLarge }
    var items: [ShareInboxItem] = []
    for provider in providers {
      try Task.checkCancellation()
      if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        items.append(try await link(provider))
      } else if provider.suggestedName == nil,
                provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                provider.registeredTypeIdentifiers.allSatisfy({ UTType($0)?.conforms(to: .text) == true }) {
        items.append(try await text(provider))
      } else if let type = provider.registeredTypeIdentifiers.first(where: {
        guard let type = UTType($0) else { return false }
        return type.conforms(to: .data) && !type.conforms(to: .url)
      }) {
        items.append(try await file(provider, type: type, folder: folder))
      } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
        items.append(try await text(provider))
      } else { throw ShareInboxQueue.Failure.invalid }
    }
    return items
  }

  private static func link(_ provider: NSItemProvider) async throws -> ShareInboxItem {
    let suggestedName = provider.suggestedName
    return try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, error in
        guard error == nil, let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)),
              url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else {
          continuation.resume(throwing: ShareInboxQueue.Failure.invalid); return
        }
        continuation.resume(returning: ShareInboxItem(kind: .link, title: String((suggestedName ?? url.host ?? "リンク").prefix(200)), value: url.absoluteString))
      }
    }
  }

  private static func text(_ provider: NSItemProvider) async throws -> ShareInboxItem {
    let suggestedName = provider.suggestedName
    return try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, error in
        guard error == nil, let text = value as? String, text.utf8.count <= 512 * 1024 else {
          continuation.resume(throwing: ShareInboxQueue.Failure.tooLarge); return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URLComponents(string: trimmed)
        let kind: ShareInboxItem.Kind = url?.scheme?.lowercased() == "https" && url?.host != nil ? .link : .text
        continuation.resume(returning: ShareInboxItem(kind: kind, title: String((suggestedName ?? (kind == .link ? url?.host : String(trimmed.prefix(40))) ?? "メモ").prefix(200)), value: trimmed))
      }
    }
  }

  private static func file(_ provider: NSItemProvider, type: String, folder: URL) async throws -> ShareInboxItem {
    let suggestedName = provider.suggestedName
    return try await withCheckedThrowingContinuation { continuation in
      provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
        do {
          guard error == nil, let url else { throw ShareInboxQueue.Failure.invalid }
          let name = try ShareInboxQueue.stageFile(url, in: folder, preferredExtension: UTType(type)?.preferredFilenameExtension)
          continuation.resume(returning: ShareInboxItem(kind: .file, title: String((suggestedName ?? url.lastPathComponent).prefix(200)), value: name))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
}
