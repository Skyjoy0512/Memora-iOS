import Foundation

extension Meeting {
  var hasAudioFiles: Bool {
    audioURL != nil || rawAudioReference != nil || !originalAudioFileNames.isEmpty || recordingAudioManifest != nil
  }

  /// Only managed, unique files participate in local reads or removal.
  /// Backup separately checks every raw reference and refuses unsafe names.
  var managedAudioFileNames: [String] {
    var references = originalAudioFileNames + (recordingAudioManifest?.fileNames ?? [])
    if let audioURL, let name = MediaFiles.reference(for: audioURL) {
      references.insert(name, at: 0)
    } else if let rawAudioReference, let url = MediaFiles.resolve(rawAudioReference),
              let name = MediaFiles.reference(for: url) {
      references.insert(name, at: 0)
    }
    var seen: Set<String> = []
    return references.compactMap { reference in
      guard MediaFiles.isPlainName(reference), let url = MediaFiles.resolve(reference),
            let name = MediaFiles.reference(for: url), seen.insert(name).inserted else { return nil }
      return name
    }
  }

  var managedAudioURLs: [URL] {
    managedAudioFileNames.compactMap { MediaFiles.resolve($0) }
  }

  mutating func removeAudioReferences() {
    audioURL = nil
    rawAudioReference = nil
    originalAudioFileNames = []
    recordingAudioManifest = nil
  }
}
