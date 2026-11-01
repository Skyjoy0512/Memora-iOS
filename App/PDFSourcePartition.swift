import Foundation
import PDFKit

/// Owns temporary, native PDF parts until the import finishes. The caller must
/// call cleanup after copying them into durable source storage.
struct PDFSourcePartition: Sendable {
  typealias Part = PDFSourcePartitionPart
  static let maximumInputBytes = 500 * 1024 * 1024
  static let maximumPartBytes = 50 * 1024 * 1024
  static let maximumOutputBytes = 400 * 1024 * 1024
  static let maximumPages = 10_000
  static let maximumParts = 100
  private static let lock = NSLock()

  var parts: [Part]
  var originalName: String
  var fingerprint: String
  var originalPageCount: Int
  private var lease: PDFSourcePartitionLease

  static func prepare(_ url: URL, pagesPerPart: Int = 100, directory: URL? = nil,
                      maximumParts: Int = Self.maximumParts) throws -> PDFSourcePartition {
    guard (1...maximumPages).contains(pagesPerPart) else { throw PDFSourcePartitionFailure.invalidPagesPerPart }
    guard (1...Self.maximumParts).contains(maximumParts) else { throw PDFSourcePartitionFailure.partLimit }
    lock.lock()
    defer { lock.unlock() }
    try Task.checkCancellation()
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let base = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("MemoraPDFPartitions", isDirectory: true)
    let inputBytes = try PDFSourcePartitionSnapshot.inputByteCount(url)
    let lease = try PDFSourcePartitionStaging.acquire(in: base, inputBytes: inputBytes)
    let folder = lease.directory
    var retained = false
    defer { if !retained { lease.remove() } }
    let snapshot = try PDFSourcePartitionSnapshot(url, in: folder)
    guard let document = PDFDocument(url: snapshot.url) else { throw PDFSourcePartitionFailure.invalidFile }
    guard !document.isLocked, !document.isEncrypted else { throw PDFSourcePartitionFailure.encrypted }
    let count = document.pageCount
    guard (1...maximumPages).contains(count) else { throw PDFSourcePartitionFailure.pageLimit }
    guard (count + pagesPerPart - 1) / pagesPerPart <= maximumParts else { throw PDFSourcePartitionFailure.partLimit }
    try rejectInteractiveDocument(document)
    let builder = PDFSourcePartitionBuilder(document: document, directory: folder, maximumParts: maximumParts)
    var first = 1
    while first <= count {
      try Task.checkCancellation()
      try builder.append(first...min(first + pagesPerPart - 1, count))
      first += pagesPerPart
    }
    try Task.checkCancellation()
    try snapshot.verifyOriginal()
    try FileManager.default.removeItem(at: snapshot.url)
    try lease.finishPreparation(outputBytes: builder.outputBytes)
    let result = PDFSourcePartition(parts: builder.parts, originalName: url.lastPathComponent,
      fingerprint: snapshot.fingerprint, originalPageCount: count, lease: lease)
    try Task.checkCancellation()
    retained = true
    return result
  }

  @discardableResult
  func cleanup() -> Bool {
    lease.remove()
  }

  func metadata(for part: Part, originalName: String? = nil) -> [String: String] {
    ["partitionOriginalFingerprint": fingerprint,
     "partitionOriginalName": originalName ?? self.originalName,
     "partitionOriginalPageCount": String(originalPageCount),
     "partitionFirstPage": String(part.firstPage), "partitionLastPage": String(part.lastPage)]
  }

  private static func rejectInteractiveDocument(_ document: PDFDocument) throws {
    guard let catalog = document.documentRef?.catalog else { throw PDFSourcePartitionFailure.invalidFile }
    var permissions: CGPDFDictionaryRef?
    if CGPDFDictionaryGetDictionary(catalog, "Perms", &permissions), let permissions {
      var signature: CGPDFObjectRef?
      if CGPDFDictionaryGetObject(permissions, "DocMDP", &signature) ||
         CGPDFDictionaryGetObject(permissions, "UR3", &signature) || CGPDFDictionaryGetObject(permissions, "UR", &signature) {
        throw PDFSourcePartitionFailure.interactiveDocument
      }
    }
    var form: CGPDFDictionaryRef?
    if CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form {
      var fields: CGPDFArrayRef?, dynamicForm: CGPDFObjectRef?
      var flags: CGPDFInteger = 0
      if CGPDFDictionaryGetObject(form, "XFA", &dynamicForm) ||
         (CGPDFDictionaryGetArray(form, "Fields", &fields) && fields.map { CGPDFArrayGetCount($0) > 0 } == true) ||
         (CGPDFDictionaryGetInteger(form, "SigFlags", &flags) && flags != 0) {
        throw PDFSourcePartitionFailure.interactiveDocument
      }
    }
  }
}
