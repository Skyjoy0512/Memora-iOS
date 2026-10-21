import SwiftUI

/// Where calls start: the person's contacts, or a keypad.
struct DialerView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var tab = Tab.keypad
  @State private var number = ""
  @State private var contacts: [CallContact] = []
  @State private var query = ""
  @State private var isCalling = false
  @State private var errorMessage: String?

  private enum Tab: String, CaseIterable, Identifiable {
    case contacts, keypad
    var id: Self { self }
    var title: String { self == .contacts ? "連絡先" : "キーパッド" }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Group {
          switch tab {
          case .keypad: keypad
          case .contacts: contactList
          }
        }
        .frame(maxHeight: .infinity)

        MemoraSectionPicker(items: Tab.allCases, selection: $tab, title: \.title)
          .padding(.horizontal, MemoraSpacing.xl)
          .padding(.vertical, MemoraSpacing.md)
      }
      .background(MemoraPalette.background)
      .navigationTitle(tab == .contacts ? "連絡先" : "")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
      .alert("電話をかけられません", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "")
      }
      .task { contacts = await CallContactsLoader.load() }
    }
  }

  // MARK: - Keypad

  private static let keys: [(digit: String, letters: String)] = [
    ("1", ""), ("2", "ABC"), ("3", "DEF"), ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
    ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"), ("*", ""), ("0", "+"), ("#", "")
  ]

  private var keypad: some View {
    VStack(spacing: 18) {
      Spacer()
      Text(number.isEmpty ? " " : number)
        .font(.system(size: 36, weight: .regular).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.horizontal, MemoraSpacing.xxl)
        .accessibilityLabel(number.isEmpty ? "番号未入力" : number)

      LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 22), count: 3), spacing: 16) {
        ForEach(Self.keys, id: \.digit) { key in
          Button {
            number.append(key.digit)
          } label: {
            VStack(spacing: 0) {
              Text(key.digit).font(.title.weight(.medium))
              if !key.letters.isEmpty {
                Text(key.letters).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
              }
            }
            .frame(width: 84, height: 84)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
            .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(key.digit)
          .simultaneousGesture(LongPressGesture().onEnded { _ in
            if key.digit == "0" { number = String(number.dropLast()) + "+" }
          })
        }
      }

      HStack(spacing: 22) {
        Color.clear.frame(width: 84, height: 84)
        callButton { call(number, name: nil) }
          .disabled(PhoneNumberFormat.e164(number) == nil || isCalling)
        Button {
          number = String(number.dropLast())
        } label: {
          Image(icon: .deleteLeft)
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(width: 84, height: 84)
        }
        .buttonStyle(.plain)
        .opacity(number.isEmpty ? 0 : 1)
        .accessibilityLabel("1文字消す")
      }
      Spacer()
    }
  }

  private func callButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Group {
        if isCalling { ProgressView().tint(.white) } else { Image(icon: .phoneFill).font(.title) }
      }
      .foregroundStyle(.white)
      .frame(width: 84, height: 84)
      .background(.green, in: Circle())
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("電話をかける")
  }

  // MARK: - Contacts

  @ViewBuilder
  private var contactList: some View {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    let shown = trimmed.isEmpty ? contacts : contacts.filter {
      $0.name.localizedCaseInsensitiveContains(trimmed) || $0.number.contains(trimmed)
    }

    if !CallContactsLoader.isAuthorized {
      ContentUnavailableView {
        Label("連絡先がつながっていません", icon: .personCropCircleBadgePlus)
      } description: {
        Text("設定アプリのMemoraで連絡先へのアクセスを許可すると、ここから電話をかけられます。")
      }
    } else {
      List(shown) { contact in
        Button {
          call(contact.number, name: contact.name)
        } label: {
          HStack(spacing: 14) {
            Text(contact.initials)
              .font(.subheadline.weight(.semibold))
              .frame(width: 44, height: 44)
              .background(Color.accentColor.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
              Text(contact.name).foregroundStyle(.primary)
              Text(contact.number).font(.subheadline).foregroundStyle(.secondary)
            }
          }
        }
        .buttonStyle(.plain)
        .accessibilityHint("電話をかけます")
      }
      .listStyle(.plain)
      .searchable(text: $query, prompt: "名前・番号で検索")
    }
  }

  // MARK: - Calling

  private func call(_ number: String, name: String?) {
    isCalling = true
    Task {
      do {
        _ = try await model.placeCall(to: number, contactName: name)
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
      isCalling = false
    }
  }
}
