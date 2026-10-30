import SwiftUI

struct ArtifactSourcesView: View {
  @Environment(MemoraModel.self) private var model
  var provenance: ArtifactProvenance?
  var meetingIDs: [UUID] = []
  var projectFileIDs: [UUID] = []
  var legacyWorkspaceID: String?
  var showsTitle = true
  @State private var selectedSource: ArtifactSourceRow?

  var body: some View {
    let rows = model.artifactSourceRows(provenance: provenance, meetingIDs: meetingIDs,
      projectFileIDs: projectFileIDs, legacyWorkspaceID: legacyWorkspaceID)
    let isUnavailable = model.isRestoring || model.isStoreProtected || model.currentTeamID != nil
      || (provenance?.workspaceID ?? legacyWorkspaceID) != model.currentTeamID || !(provenance?.isValid ?? true)
    if !rows.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        if showsTitle { Text("参照した情報").font(.headline) }
        ForEach(rows) { row in
          ArtifactSourceLink(row: row) { selectedSource = row }
        }
        if let date = provenance?.capturedAt {
          Text("参照日時: " + date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP")))).font(.caption).foregroundStyle(.secondary)
        }
        Text(provenance?.isComplete == true
          ? "参照した情報です。本文の各記述との一致は未検証です。"
          : "出典は一部のみ記録されています。本文の各記述との一致は未検証です。")
          .font(.caption).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .sheet(item: $selectedSource) { row in
        ArtifactSourceDetailView(target: row.target, workspaceID: provenance?.workspaceID ?? legacyWorkspaceID)
      }
    } else if (provenance != nil && isUnavailable) || !meetingIDs.isEmpty || !projectFileIDs.isEmpty {
      Text("現在のワークスペースで出典を確認できません。")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }
}
