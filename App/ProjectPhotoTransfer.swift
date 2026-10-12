import CoreTransferable
import UniformTypeIdentifiers

struct ProjectPhotoTransfer: Transferable {
  var receipt: ProjectSourceFiles.Receipt

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .image) { file in
      ProjectPhotoTransfer(receipt: try await ProjectSourceFiles.shared.copy(file.file))
    }
  }
}
