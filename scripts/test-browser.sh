#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/snapdrive-browser-checks.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "${SNAPDRIVE_MODULE_CACHE:-$test_dir/module-cache}" \
  "$project_dir/Sources/BrowserHost/BrowserHostCore.swift" "$project_dir/Tests/BrowserHostChecks.swift" -o "$test_dir/BrowserHostChecks"
"$test_dir/BrowserHostChecks"
node "$project_dir/Tests/BrowserExtensionChecks.js"
node "$project_dir/Tests/BrowserWorkerChecks.js"
node "$project_dir/Tests/BrowserPageChecks.js"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "${SNAPDRIVE_MODULE_CACHE:-$test_dir/module-cache}" \
  "$project_dir/Sources/SnapDrive/BrowserBridge.swift" "$project_dir/Tests/BrowserSetupChecks.swift" -o "$test_dir/BrowserSetupChecks"
"$test_dir/BrowserSetupChecks"
