#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-source-storage.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export MEMORA_WORKSPACE_FILES_DIRECTORY="$check_dir/workspace"
export SWIFT_BACKTRACE=enable=no
python3 - "$check_dir/ProjectLinks.swift" <<'PY'
from pathlib import Path
import sys
source = Path('App/MemoraModel+ProjectSources.swift').read_text()
method = source.split('  @discardableResult', 1)[1].split('  func performProjectSourcePreparation', 1)[0]
# The link is stored through the same link path the capture coordinator uses,
# so the storage check keeps testing production storage after that rewiring.
coordinator = Path('App/MemoraModel+CaptureCoordinator.swift').read_text()
begin = coordinator.index('  private func captureLink(')
end = coordinator.index('  /// Copied text, stored as a note', begin)
capture_link = coordinator[begin:end]
method = method.replace(
    '    let intent = CaptureIntent.url(link.url)\n', '')
method = method.replace(
    '    let outcome = await capture(intent, context: context, title: title, removing: removing)',
    '    let outcome = await captureLink(link.url, context: context, isMeeting: false,\n'
    '      sourceID: nil, metadata: [:], title: title, removing: removing)')
Path(sys.argv[1]).write_text('import Foundation\nextension MemoraModel {\n  @discardableResult'
  + method + capture_link + '}\n')
PY
swiftc App/SummaryKnowledge.swift App/SourceSummaryOptions.swift App/SummaryLength.swift App/SummaryEngineChoice.swift -D MEMORA_HOST_CHECKS -D MEMORA_DRAFT_STORAGE_CHECKS Shared/MemoraIcon.swift App/LocalStore.swift App/MemoraSpace.swift \
  App/RecordPrivacy.swift App/SummarySensitivity.swift App/ProjectSource.swift App/ProjectSourceText.swift \
  App/ProjectSourceFiles.swift App/ProjectSourceTextReader.swift App/IdentifiableIndex.swift App/ProjectCitation.swift App/PersistenceFailurePresentation.swift \
  App/MemoraModel+ProjectSourceStorage.swift App/ProjectSourceURL.swift App/DraftStore.swift App/LocalSaveFailure.swift \
  App/LocalImportContext.swift App/CaptureOutcome.swift "$check_dir/ProjectLinks.swift" \
  tools/checks/ProjectSourceStorageFixture.swift tools/checks/DraftStoreRecordFixture.swift \
  tools/checks/ProjectSourceStorageChecks.swift -lsqlite3 -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
