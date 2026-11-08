#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/snapdrive-window-checks.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "${SNAPDRIVE_MODULE_CACHE:-$test_dir/module-cache}" \
  "$project_dir/Sources/SnapDrive/WindowChrome.swift" "$project_dir/Tests/WindowChecks.swift" -o "$test_dir/WindowChecks"
"$test_dir/WindowChecks"
