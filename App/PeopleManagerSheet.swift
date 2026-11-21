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
  @State private var isPhotoLoading = false
  @State private var editingPhoto: PhotoEditRequest?
  @State private var editingPerson: Person?
  @State private var deletingPerson: Person?
  @State private var deleteFailed = false

  private enum PhotoTarget: Equatable {
    case new
    case person(UUID)
  }

  var body: some View {
    let canDeletePerson = model.currentTeamID == nil && !model.isRestoring && !model.isStoreProtected
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
            .disabled(isPhotoLoading)

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

                Button {
                  editingPerson = person
                } label: {
                  VStack(alignment: .leading, spacing: MemoraSpacing.xxs) {
                    Text(person.name)
                    if let note = person.note, !note.isEmpty {
                      Text(note)
                        .font(MemoraTypography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                  }
                  .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(person.name)を編集")
                .accessibilityValue(person.note ?? "")
                .accessibilityActions {
                  if canDeletePerson {
                    Button("削除") { deletingPerson = person }
                  }
                }

                Button {
                  photoTarget = .person(person.id)
                  isPhotoPickerPresented = true
                } label: {
                  Label("\(person.name)の写真を変更", icon: .photo).labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isPhotoLoading)
                .foregroundStyle(.secondary)
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canDeletePerson {
                  Button("削除", icon: .trash, role: .destructive) { deletingPerson = person }
                }
                Button("編集", icon: .pencil) { editingPerson = person }
              }
            }
          }
        }
      }
      .navigationTitle("人物")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("完了", icon: .checkmark) { dismiss() }
        }
      }
      .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoItem, matching: .images)
      .loadsSelectedPhoto($photoItem, isLoading: $isPhotoLoading) { data in
        editingPhoto = PhotoEditRequest(data: data)
      }
      .sheet(item: $editingPerson) { person in
        PersonEditSheet(personID: person.id)
      }
      .alert("この人物を削除しますか？", isPresented: Binding(
        get: { deletingPerson != nil }, set: { if !$0 { deletingPerson = nil } }
      ), presenting: deletingPerson) { person in
        Button("削除", role: .destructive) {
          if !model.deletePerson(person.id) { deleteFailed = true }
        }
        Button("キャンセル", role: .cancel) {}
      } message: { person in
        let label = PersonSelectionOption.options(model.people).first { $0.id == person.id }?.label ?? person.name
        Text("「\(label)」と、記録に付いた参加者の関連付けを削除します。記録・タスク・ジャーナルの内容は残ります。同じ名前で登録し直しても、関連付けは戻りません。")
      }
      .alert("人物を削除できませんでした", isPresented: $deleteFailed) {
        Button("閉じる", role: .cancel) {}
      } message: {
        Text("保存先の状態を確認し、もう一度お試しください。")
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
