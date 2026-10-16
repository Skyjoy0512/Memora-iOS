import MessageUI
import SwiftUI

/// Opens the agent's email in Mail's composer, so the person reviews and sends
/// it. Without a Mail account it falls back to the share sheet with the text.
struct MailDraftSheet: View {
  @Environment(MemoraModel.self) private var model
  var onFinish: () -> Void
  @State private var edited: MailDraft
  @State private var to: String
  @State private var cc: String
  @State private var bcc: String
  @State private var opensMail = false
  @State private var failure = false

  init(draft: MailDraft, onFinish: @escaping () -> Void) {
    self.onFinish = onFinish
    _edited = State(initialValue: draft)
    _to = State(initialValue: draft.recipients.joined(separator: ", "))
    _cc = State(initialValue: draft.cc.joined(separator: ", "))
    _bcc = State(initialValue: draft.bcc.joined(separator: ", "))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("宛先（不明なら空欄）", text: $to).keyboardType(.emailAddress).textInputAutocapitalization(.never)
          TextField("CC", text: $cc).keyboardType(.emailAddress).textInputAutocapitalization(.never)
          TextField("BCC", text: $bcc).keyboardType(.emailAddress).textInputAutocapitalization(.never)
          TextField("件名", text: $edited.subject)
        } footer: { Text("Memora内の下書きです。送信はMailで本人が行います。宛先は推測で補いません。") }
        if edited.workspaceID == model.currentTeamID, !edited.recordIDs.isEmpty {
          Section("元の記録") {
            ForEach(edited.recordIDs, id: \.self) { id in
              if let meeting = model.meeting(id: id) {
                NavigationLink { MeetingDetailView(meetingID: id, showsLocalPlaybackBar: true) } label: { Text(meeting.displayTitle) }
              }
            }
          }
        }
        Section("本文") { TextEditor(text: $edited.body).frame(minHeight: 240).accessibilityLabel("メール本文") }
        Section {
          Button("本文をコピー", icon: .docOnDoc) { UIPasteboard.general.string = edited.body }
          ShareLink(item: edited.plainText) { Label("共有", icon: .squareAndArrowUp) }
          Button("Mailで開く", icon: .envelope) { if save() { opensMail = true } }
            .disabled(!MFMailComposeViewController.canSendMail())
          if !MFMailComposeViewController.canSendMail() { Text("Mailのアカウントが未設定です。本文のコピー・共有を利用できます。").font(.footnote).foregroundStyle(.secondary) }
        }
      }
      .tint(.primary)
      .navigationTitle("メール下書き").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { ToolbarIconButton("閉じる", icon: .xmark, action: onFinish) }
        ToolbarItem(placement: .confirmationAction) { ToolbarIconButton("保存", icon: .checkmark) { if save() { onFinish() } } }
      }
      .onAppear {
        guard edited.workspaceID == model.currentTeamID else { return }
        edited.body = DraftStore.load("mail.\(edited.id).body") ?? edited.body
        edited.subject = DraftStore.load("mail.\(edited.id).subject") ?? edited.subject
        to = DraftStore.load("mail.\(edited.id).to") ?? to
        cc = DraftStore.load("mail.\(edited.id).cc") ?? cc
        bcc = DraftStore.load("mail.\(edited.id).bcc") ?? bcc
      }
      .onChange(of: edited.body) { _, value in keepDraft(value, field: "body") }
      .onChange(of: edited.subject) { _, value in keepDraft(value, field: "subject") }
      .onChange(of: to) { _, value in keepDraft(value, field: "to") }
      .onChange(of: cc) { _, value in keepDraft(value, field: "cc") }
      .onChange(of: bcc) { _, value in keepDraft(value, field: "bcc") }
      .sheet(isPresented: $opensMail) { MailComposer(draft: edited) { opensMail = false }.ignoresSafeArea() }
      .alert("保存できませんでした", isPresented: $failure) { Button("閉じる", role: .cancel) {} } message: { Text("宛先にはメールアドレスをカンマで区切って入力してください。保存先やワークスペースも確認してください。") }
    }
  }

  private func keepDraft(_ value: String, field: String) {
    guard edited.workspaceID == model.currentTeamID, !model.isStoreProtected, value.utf8.count <= 400_000 else { return }
    DraftStore.save(value, key: "mail.\(edited.id).\(field)")
  }

  private func save() -> Bool {
    func addresses(_ value: String) -> [String] { value.components(separatedBy: CharacterSet(charactersIn: ",;\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    edited.recipients = addresses(to); edited.cc = addresses(cc); edited.bcc = addresses(bcc); edited.updatedAt = .now
    let stored = model.saveMailDraft(edited)
    failure = !stored
    if stored { for field in ["body", "subject", "to", "cc", "bcc"] { DraftStore.clear("mail.\(edited.id).\(field)") } }
    return stored
  }
}

private struct MailComposer: UIViewControllerRepresentable {
  var draft: MailDraft
  var onFinish: () -> Void

  func makeUIViewController(context: Context) -> MFMailComposeViewController {
    let controller = MFMailComposeViewController()
    controller.setToRecipients(draft.recipients)
    controller.setCcRecipients(draft.cc)
    controller.setBccRecipients(draft.bcc)
    controller.setSubject(draft.subject)
    controller.setMessageBody(draft.body, isHTML: false)
    controller.mailComposeDelegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onFinish: onFinish)
  }

  final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
    var onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
      self.onFinish = onFinish
    }

    func mailComposeController(
      _ controller: MFMailComposeViewController,
      didFinishWith result: MFMailComposeResult,
      error: (any Error)?
    ) {
      onFinish()
    }
  }
}
