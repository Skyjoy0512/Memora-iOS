import Foundation

struct PDFSourcePartitionRequest: Identifiable {
  var id = UUID()
  var url: URL
  var context: LocalImportContext
  var originalSource: ProjectSource? = nil
}
