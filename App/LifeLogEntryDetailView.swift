import SwiftUI
import UIKit

/// One journal entry in full: its photo, text, and where it came from, with
/// editing and deleting.
struct LifeLogEntryDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var entryID: UUID
  @State private var isEditing = false
  @State private var isDeleting = false
  @State private var isExcludingPlace = false
  @State private var isViewingPhoto = false
  @State private var isPrivacyPresented = false

  var body: some View {
    NavigationStack {
      Group {
        if let entry = currentEntry {
          content(entry)
        } else {
          ContentUnavailableView("記録が見つかりません", icon: .docQuestionmark)
        }
      }
      .navigationTitle("記録")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            Button("プライバシーと外部送信", icon: .lockShield) { isPrivacyPresented = true }
            Button("編集", icon: .pencil) { isEditing = true }
            if let entry = currentEntry, entry.latitude != nil, entry.longitude != nil {
              Button("この場所を今後記録しない", icon: .mappinSlash) {
                isExcludingPlace = true
              }
            }
            Button("削除", icon: .trash, role: .destructive) { isDeleting = true }
          } label: {
            ToolbarActionLabel("その他", icon: .ellipsis)
          }
        }
      }
      .sheet(isPresented: $isEditing) {
        if let entry = currentEntry {
          LifeLogEditSheet(entry: entry)
        }
      }
      .sheet(isPresented: $isPrivacyPresented) {
        RecordPrivacySettingsView(target: .journal(entryID))
      }
      .fullScreenCover(isPresented: $isViewingPhoto) {
        if let image = photo {
          LifeLogPhotoViewer(image: image)
        }
      }
      .confirmationDialog("この記録を削除しますか？", isPresented: $isDeleting, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          model.deleteLifeLogEntry(entryID)
          dismiss()
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("「最近削除した項目」に移動します。30日間は元に戻せます。")
      }
      .confirmationDialog("この場所を今後記録しない", isPresented: $isExcludingPlace, titleVisibility: .visible) {
        Button("記録しない（この記録も削除）", role: .destructive) {
          excludeCurrentPlace()
          model.deleteLifeLogEntry(entryID)
          dismiss()
        }
        Button("記録しない（記録は残す）") {
          excludeCurrentPlace()
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("この場所の周辺では自動の記録を行いません。")
      }
      .task(id: currentEntry?.photoFileName) {
        await loadPhoto()
      }
    }
  }

  private var currentEntry: LifeLogEntry? {
    model.lifeLogEntries.first { $0.id == entryID }
  }

  /// Adds this record's place to the excluded list, so the logger skips it.
  private func excludeCurrentPlace() {
    guard let entry = currentEntry, let latitude = entry.latitude, let longitude = entry.longitude else { return }
    AutoLocationLogger.addExcludedPlace(name: entry.title, latitude: latitude, longitude: longitude)
  }

  @State private var photo: UIImage?

  /// Reads the photo at the size it is shown, off the main thread.
  private func loadPhoto() async {
    guard let name = currentEntry?.photoFileName else {
      photo = nil
      return
    }
    let loaded = await MediaImageCache.photo(named: name)
    guard !Task.isCancelled, currentEntry?.photoFileName == name else { return }
    photo = loaded
  }

  private func content(_ entry: LifeLogEntry) -> some View {
    let people = PersonSelectionOption.options(model.people).filter { entry.personIDs.contains($0.id) }
    let missingCount = Set(entry.personIDs).subtracting(Set(people.map(\.id))).count
    return ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 8) {
          Image(icon: entry.kind.symbol)
          Text(entry.kind.label)
          Text("·")
          Text(entry.occurredAt.formatted(date: .abbreviated, time: .shortened))
        }
        .font(.subheadline)
        .foregroundStyle(.primary)

        if let image = photo {
          Button {
            isViewingPhoto = true
          } label: {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(maxWidth: .infinity)
              .frame(height: 260)
              .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("写真を拡大")
        }

        Text(entry.title)
          .font(.title2.bold())

        if !entry.summary.isEmpty {
          Text(entry.summary)
            .font(.body)
            .lineSpacing(4)
        }
        if !entry.personIDs.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("関連する人物").font(.subheadline.weight(.medium))
            ForEach(people) { option in Text(option.label).font(.subheadline) }
            if missingCount > 0 { Text("削除済みの人物 \(missingCount)人").font(.subheadline) }
          }
          .foregroundStyle(.secondary)
          .accessibilityElement(children: .combine)
        }

        if let locationName = entry.locationName, !locationName.isEmpty {
          Label(locationName, icon: .locationFill)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if (entry.kind == .location || entry.kind == .event),
           let place = JournalPlace(name: entry.locationName ?? entry.title,
             latitude: entry.latitude, longitude: entry.longitude) {
          JournalMapPreview(place: place, date: entry.occurredAt)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
    }
    .background(Color(uiColor: .systemBackground))
  }
}

/// A photo at full size, pinch to zoom.
private struct LifeLogPhotoViewer: View {
  @Environment(\.dismiss) private var dismiss
  var image: UIImage
  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .scaleEffect(scale)
        .gesture(
          MagnifyGesture()
            .onChanged { value in
              let delta = value.magnification / (lastScale == 0 ? 1 : lastScale)
              lastScale = value.magnification
              scale = min(max(1, scale * delta), 6)
            }
            .onEnded { _ in
              lastScale = 1
            }
        )

      VStack {
        HStack {
          Spacer()
          Button("写真を閉じる", icon: .xmark) {
            dismiss()
          }
          .labelStyle(.iconOnly)
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(.white.opacity(0.12), in: Circle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)

        Spacer()
      }
    }
  }
}
