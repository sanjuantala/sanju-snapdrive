#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
export SNAPDRIVE_MODULE_CACHE="${SNAPDRIVE_MODULE_CACHE:-${TMPDIR:-/tmp}/snapdrive-shared-module-cache}"
mkdir -p "$SNAPDRIVE_MODULE_CACHE"
for suite in image-engine interaction editor icons capture window drive browser ui; do
  "$project_dir/scripts/test-$suite.sh"
done
printf 'PASS all SnapDrive check suites completed. Review any explicit environment-dependent SKIP lines.\n'
