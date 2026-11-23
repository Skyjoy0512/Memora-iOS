#!/bin/bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  printf 'usage: %s [path]\n' "$0" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd "$script_dir/../.." && pwd -P)
scan_path=${1:-$repo_root}

if ! command -v gitleaks >/dev/null 2>&1; then
  printf 'Leak scan skipped: gitleaks is not installed. Install gitleaks to scan %s.\n' "$scan_path"
  exit 0
fi

status=0
gitleaks dir "$scan_path" || status=$?
exit "$status"
