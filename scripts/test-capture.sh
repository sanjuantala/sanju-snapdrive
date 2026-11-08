#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/snapdrive-capture-checks.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cp "$project_dir/Sources/SnapDrive/CaptureService.swift" "$test_dir/CaptureService.swift"
cp "$project_dir/Tests/CaptureChecks.swift" "$test_dir/CaptureChecks.swift"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "${SNAPDRIVE_MODULE_CACHE:-$test_dir/module-cache}" \
  "$test_dir/CaptureService.swift" "$test_dir/CaptureChecks.swift" \
  -o "$test_dir/CaptureChecks"
"$test_dir/CaptureChecks"
