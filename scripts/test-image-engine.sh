#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/snapdrive-engine-checks.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
arch="$(uname -m)"
cp "$project_dir/Sources/SnapDrive/ImageEngine.swift" "$test_dir/ImageEngine.swift"
cp "$project_dir/Tests/ImageEngineChecks.swift" "$test_dir/ImageEngineChecks.swift"
xcrun swiftc -target "${arch}-apple-macos13.0" \
  -module-cache-path "${SNAPDRIVE_MODULE_CACHE:-$test_dir/module-cache}" \
  "$test_dir/ImageEngine.swift" \
  "$test_dir/ImageEngineChecks.swift" \
  -o "$test_dir/ImageEngineChecks"
"$test_dir/ImageEngineChecks"
