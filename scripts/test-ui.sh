#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/snapdrive-ui-checks.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
for source in "$project_dir"/Sources/SnapDrive/*.swift; do
  if [[ "$(basename "$source")" != "SnapDriveApp.swift" ]]; then cp "$source" "$test_dir/"; fi
done
cp "$project_dir/Tests/UIActionChecks.swift" "$test_dir/"
for resource in Icons Backgrounds; do
  if [[ -d "$project_dir/Resources/$resource" ]]; then cp -R "$project_dir/Resources/$resource" "$test_dir/"; fi
done
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "${SNAPDRIVE_MODULE_CACHE:-$test_dir/module-cache}" \
  "$test_dir"/*.swift -o "$test_dir/UIActionChecks"
"$test_dir/UIActionChecks"
