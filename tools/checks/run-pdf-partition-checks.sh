#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${MEMORA_CHECK_ROOT:-${TMPDIR:-/tmp}}/memora-pdf-partition.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
export MEMORA_WORKSPACE_FILES_DIRECTORY="$check_dir/workspace"
export SWIFT_BACKTRACE=enable=no
swiftc App/SummaryKnowledge.swift -D MEMORA_HOST_CHECKS -D MEMORA_SOURCE_IMPORT_CHECKS -D MEMORA_PDF_PARTITION_CHECKS -D MEMORA_SHARE_PDF_CHECKS \
  App/SourceSummaryOptions.swift App/SummaryLength.swift App/SummaryEngineChoice.swift Shared/MemoraIcon.swift \
  App/RecordPrivacy.swift App/SummarySensitivity.swift App/ProjectSource.swift App/ProjectSourceText.swift \
  App/ProjectSourceFiles.swift App/ProjectSourceTextReader.swift App/LocalStore.swift App/MemoraSpace.swift \
  App/IdentifiableIndex.swift App/ProjectCitation.swift App/PersistenceFailurePresentation.swift \
  App/PDFSourcePartition.swift App/PDFSourcePartitionPart.swift App/PDFSourcePartitionSnapshot.swift \
  App/PDFSourcePartitionBuilder.swift App/PDFSourcePartitionFailure.swift App/PDFSourcePartitionImportFailure.swift \
  App/PDFSourcePartitionLease.swift App/PDFSourcePartitionStaging.swift \
  App/PDFSourceCopyLease.swift App/PDFSourceCopyJournal.swift \
  App/PDFSourcePartitioning.swift App/SourceProcessingQueue.swift App/SourceIntake.swift \
  App/ProjectSourcePreparationContext.swift App/LocalImportContext.swift \
  App/MemoraModel+ProjectSourceStorage.swift App/MemoraModel+SourceIntake.swift App/MemoraModel+PDFSourcePartition.swift \
  App/MemoraModel+ProjectSourceImport.swift App/MemoraModel+InformationSources.swift \
  App/MemoraModel+ShareInbox.swift App/ProjectSourceURL.swift \
  Shared/ShareInbox/ShareInboxQueue.swift Shared/ShareInbox/ShareInboxRequest.swift \
  Shared/ShareInbox/ShareInboxItem.swift Shared/ShareInbox/ShareInboxProject.swift tools/checks/SharePDFCheckConfiguration.swift \
  tools/checks/ProjectSourceStorageFixture.swift tools/checks/PDFPartitionChecks.swift -lsqlite3 -o "$check_dir/checks"
"$check_dir/checks" "$check_dir"
