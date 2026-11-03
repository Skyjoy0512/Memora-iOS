import CryptoKit
import Foundation
import PhotosUI
import SwiftUI

extension MemoraModel {
  func importCapturePhotos(_ items: [PhotosPickerItem], context: LocalImportContext) async {
    guard context.isCurrent(in: self), !items.isEmpty, items.count <= 6 else { return }
    do {
      var lastID: UUID?
      for item in items {
        guard let id = try await importProjectSource(title: "写真", context: context,
          presentsErrorsLocally: true, waitsForPreparation: false, load: {
            try await item.loadTransferable(type: ProjectPhotoTransfer.self)?.receipt
          }) else { throw ProjectSourceFiles.Failure.invalidFile }
        lastID = id
      }
      openCaptureSource(lastID, context: context)
    } catch {
      if context.isCurrent(in: self) { importErrorMessage = "写真を保存できませんでした。保存先と空き容量を確認して再試行してください。" }
    }
  }

  func importCameraPhoto(_ data: Data, context: LocalImportContext) async {
    guard context.isCurrent(in: self), !data.isEmpty,
          data.count <= ProjectSourceFiles.maximumFileBytes else { return }
    do {
      let id = try await importProjectSource(title: "撮影した資料", context: context,
        presentsErrorsLocally: true, waitsForPreparation: false) {
          let fingerprint = await Task.detached(priority: .utility) {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
          }.value
          let name = try await ProjectSourceFiles.shared.write(data, extension: "jpg")
          return ProjectSourceFiles.Receipt(reference: name, fingerprint: fingerprint)
        }
      guard let id else { throw ProjectSourceFiles.Failure.invalidFile }
      openCaptureSource(id, context: context)
    } catch {
      if context.isCurrent(in: self) { importErrorMessage = "撮影した資料を保存できませんでした。空き容量を確認して再試行してください。" }
    }
  }

  private func openCaptureSource(_ id: UUID?, context: LocalImportContext) {
    guard let id, context.isCurrent(in: self), source(id: id)?.projectID == context.projectID else { return }
    selectedTab = .library
    librarySection = .files
    libraryPath = [.projectSource(id)]
  }
}
