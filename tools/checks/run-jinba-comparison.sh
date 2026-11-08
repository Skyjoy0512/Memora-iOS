#!/bin/bash
# Regenerates Memora's 65 layouts and compares them with the licensed Jinba
# catalog. The PNGs come from the app's own CoreGraphics preview: this is a
# mechanical margin/density/overlap check, not a PowerPoint render or a visual
# approval. Set MEMORA_RENDER_OFFICE=1 to also try the local Office apps.
set -euo pipefail
cd "$(dirname "$0")/../.."

catalog="${MEMORA_JINBA_CATALOG:-/Volumes/WorkspaceSSD/Development/memora-integration-lC8LwD/upstream/assets/SlideCatalog_16x9.pdf}"
report="${MEMORA_JINBA_REPORT:-${TMPDIR:-/tmp}/memora-jinba-comparison.md}"
if [ ! -f "$catalog" ]; then
  echo "Jinba catalog not found: $catalog" >&2
  echo "Set MEMORA_JINBA_CATALOG to the licensed SlideCatalog_16x9.pdf." >&2
  exit 2
fi

run_output=$(bash tools/checks/run-presentation-checks.sh 2>&1)
printf '%s\n' "$run_output" | tail -3
output=$(printf '%s\n' "$run_output" | sed -n 's/^Presentation artifacts: //p' | tail -1)
if [ -z "$output" ] || [ ! -d "$output" ]; then
  echo "Presentation output directory was not reported" >&2
  exit 1
fi

check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-jinba-compare.XXXXXX")
swiftc App/SlideArchetype.swift tools/checks/compare-jinba-catalog.swift -o "$check_dir/compare"
"$check_dir/compare" "$catalog" "$output" "$report"
echo "Host-preview comparison: $report"

if [ "${MEMORA_RENDER_OFFICE:-0}" = "1" ]; then
  # These apps may show a first-run/sign-in dialog; the scripts time out rather
  # than force-quitting or clicking a dialog. A failure here is reported as an
  # unverified render, never as a pass.
  rendered="$output/catalog-65-powerpoint.pdf"
  if osascript tools/checks/render-powerpoint.applescript "$output/catalog-65.pptx" "$rendered"; then
    echo "PowerPoint PDF: $rendered"
  else
    echo "PowerPoint render failed; the 65 layouts remain unverified on device/Office." >&2
    exit 3
  fi
fi
