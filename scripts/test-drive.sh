#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/snapdrive-drive-checks.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
arch="$(uname -m)"
xcrun swiftc -target "${arch}-apple-macos13.0" \
  -module-cache-path "${SNAPDRIVE_MODULE_CACHE:-$test_dir/module-cache}" \
  "$project_dir/Sources/SnapDrive/GoogleAppConfiguration.swift" \
  "$project_dir/Sources/SnapDrive/DriveService.swift" \
  "$project_dir/Sources/SnapDrive/LinkService.swift" \
  "$project_dir/Tests/DriveChecks.swift" \
  "$project_dir/Tests/DriveLinkChecks.swift" \
  "$project_dir/Tests/DriveOAuthChecks.swift" \
  -o "$test_dir/DriveChecks"
"$test_dir/DriveChecks"
