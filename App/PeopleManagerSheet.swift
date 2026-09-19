import PhotosUI
import SwiftUI
import UIKit

/// Adds people, gives them a photo, and removes them. Reachable from the
/// Home people strip.
struct PeopleManagerSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  @State private var newName = ""
  @State private var newPhotoData: Data?
  @State private var isPhotoPickerPresented = false
  @State private var photoTarget: PhotoTarget?
  @State private var photoItem: PhotosPickerItem?

  private enum PhotoTarget: Equatable {
    case new
    case person(UUID)
  }

  var body: some View {
    NavigationStack {
      List {
        Section("新規作成") {
          HStack(spacing: 12) {
            Button {
              photoTarget = .new
              isPhotoPickerPresented = true
            } label: {
              PersonAvatar(
                name: newName.isEmpty ? "?" : newName,
                size: 44,
                photoData: newPhotoData
              )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("写真を選ぶ")

            TextField("名前", text: $newName)
              .onSubmit(add)

            Button("追加") { add() }
              .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }

        if !model.people.isEmpty {
          Section("人") {
            ForEach(model.people) { person in
              HStack(spacing: 12) {
                PersonAvatar(name: person.name, size: 44, photoData: person.photoData)

                Text(person.name)

                Spacer()

                Button("写真を変更", systemImage: "photo") {
                  photoTarget = .person(person.id)
                  isPhotoPickerPresented = true
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
              }
            }
            .onDelete { indexSet in
              for index in indexSet {
                model.deletePerson(model.people[index].id)
              }
            }
          }
        }
      }
      .navigationTitle("人")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
      .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoItem, matching: .images)
      .onChange(of: photoItem) { _, item in
        guard let item else { return }
        Task { await applyPhoto(item) }
      }
    }
  }

  private func add() {
    guard let person = model.addPerson(name: newName) else { return }
    if let newPhotoData {
      model.setPersonPhoto(person.id, data: newPhotoData)
    }
    newName = ""
    newPhotoData = nil
  }

  private func applyPhoto(_ item: PhotosPickerItem) async {
    defer { photoItem = nil }

    guard let data = try? await item.loadTransferable(type: Data.self),
          let small = Self.downscaled(data) else { return }

    switch photoTarget {
    case .new:
      newPhotoData = small
    case .person(let id):
      model.setPersonPhoto(id, data: small)
    case nil:
      break
    }
  }

  private static func downscaled(_ data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }

    let maxSide: CGFloat = 320
    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

    let resized = UIGraphicsImageRenderer(size: size).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    return resized.jpegData(compressionQuality: 0.8)
  }
}
