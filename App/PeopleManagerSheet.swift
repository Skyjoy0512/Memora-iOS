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
  @State private var editingPhoto: PhotoEditRequest?
  @State private var editingPerson: Person?

  private enum PhotoTarget: Equatable {
    case new
    case person(UUID)
  }

  var body: some View {
    NavigationStack {
      MemoraList {
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

                VStack(alignment: .leading, spacing: 2) {
                  Text(person.name)
                  if let note = person.note, !note.isEmpty {
                    Text(note)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { editingPerson = person }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(person.name)を編集")

                Button("写真を変更", icon: .photo) {
                  photoTarget = .person(person.id)
                  isPhotoPickerPresented = true
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
              }
              .swipeActions(edge: .trailing) {
                Button("編集", icon: .pencil) { editingPerson = person }
              }
            }
            .onDelete { indexSet in
              let ids = indexSet.compactMap { model.people.indices.contains($0) ? model.people[$0].id : nil }
              for id in ids { model.deletePerson(id) }
            }
          }
        }
      }
      .navigationTitle("人")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("完了", icon: .checkmark) { dismiss() }
        }
      }
      .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoItem, matching: .images)
      .onChange(of: photoItem) { _, item in
        guard let item else { return }
        Task {
          guard let data = try? await item.loadTransferable(type: Data.self) else { return }
          photoItem = nil
          editingPhoto = PhotoEditRequest(data: data)
        }
      }
      .sheet(item: $editingPerson) { person in
        PersonEditSheet(personID: person.id)
      }
      .sheet(item: $editingPhoto) { request in
        PhotoEditorView(source: request.data) { edited in
          guard let small = ImageDownscale.jpeg(edited) else { return }
          switch photoTarget {
          case .new:
            newPhotoData = small
          case .person(let id):
            model.setPersonPhoto(id, data: small)
          case nil:
            break
          }
        }
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
}
