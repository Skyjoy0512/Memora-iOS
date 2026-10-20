import PhotosUI
import SwiftUI

/// Edits the picture and name shown on Settings and each tab's top-right
/// button: a Memoji or emoji on a background color, or a cropped photo.
struct ProfileEditorView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var isStickerInputActive = false
  @State private var isPhotoPickerPresented = false
  @State private var photoItem: PhotosPickerItem?
  @State private var editingPhoto: PhotoEditRequest?
  @State private var saveFailed = false

  private var profile: UserProfile { model.profile }

  var body: some View {
    @Bindable var profile = profile

    NavigationStack {
      Form {
        Section {
          VStack(spacing: 12) {
            Button {
              isStickerInputActive = true
            } label: {
              ProfileAvatar(profile: profile, size: 132)
                .overlay(alignment: .bottomTrailing) {
                  Image(icon: .faceSmilingFill, size: 20)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.tint, in: Circle())
                    .overlay { Circle().stroke(Color(uiColor: .systemGroupedBackground), lineWidth: 3) }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ミー文字・絵文字を選ぶ")

            // Kept in the layout (not hidden) so it can own the keyboard.
            StickerInputField(isActive: $isStickerInputActive) { image in
              saveFailed = !profile.setAvatar(image, kind: .sticker)
              isStickerInputActive = false
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
          }
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
        }

        Section("名前") {
          TextField("表示する名前", text: $profile.name)
            .textContentType(.name)
            .submitLabel(.done)
        }

        Section {
          Button("ミー文字・絵文字を選ぶ", icon: .faceSmiling) {
            isStickerInputActive = true
          }

          Button("写真を選ぶ", icon: .photoOnRectangle) {
            isPhotoPickerPresented = true
          }

          if profile.avatarKind == .photo {
            Button("写真を編集", icon: .crop) {
              if let data = profile.sourcePhoto() ?? profile.avatar?.pngData() {
                editingPhoto = PhotoEditRequest(data: data)
              }
            }
          }

          if profile.avatarKind != .none {
            Button("写真を削除", icon: .trash, role: .destructive) {
              profile.removeAvatar()
            }
          }
        } header: {
          Text("写真")
        } footer: {
          Text("ミー文字は、絵文字キーボードの左端にあるステッカーから選べます。出てこないときは、iPhoneの「設定」>「一般」>「キーボード」で「ミー文字ステッカー」をオンにしてください。")
        }

        if profile.avatarKind == .sticker {
          Section("背景") {
            backgroundPicker(selection: $profile.background)
          }
        }
      }
      .navigationTitle("プロフィール")
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
          let data = try? await item.loadTransferable(type: Data.self)
          photoItem = nil
          if let data {
            editingPhoto = PhotoEditRequest(data: data)
          }
        }
      }
      .sheet(item: $editingPhoto) { request in
        PhotoEditorView(source: request.data, lockedAspect: .square) { edited in
          guard let image = UIImage(data: edited) else { return }
          saveFailed = !profile.setAvatar(image, kind: .photo, sourcePhoto: request.data)
        }
      }
      .alert("写真を保存できませんでした", isPresented: $saveFailed) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("iPhoneの空き容量を確認して、もう一度お試しください。")
      }
      .interactionFeedback(.selection, trigger: profile.avatar)
    }
  }

  private func backgroundPicker(selection: Binding<AvatarBackground>) -> some View {
    HStack(spacing: 0) {
      ForEach(AvatarBackground.allCases) { option in
        Button {
          withAnimation(.snappy) {
            selection.wrappedValue = option
          }
        } label: {
          Circle()
            .fill(option.gradient)
            .frame(width: 32, height: 32)
            .padding(MemoraSpacing.xs)
            .overlay {
              if selection.wrappedValue == option {
                Circle().strokeBorder(.tint, lineWidth: 2.5)
              }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(selection.wrappedValue == option ? .isSelected : [])
      }
    }
  }
}
