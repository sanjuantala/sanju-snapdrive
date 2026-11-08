#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/snapdrive-editor-checks.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
sources=(ImageEngine.swift EditorModel.swift ImageImportService.swift EditorCanvas.swift EditorInteraction.swift UIState.swift DriveService.swift GoogleAppConfiguration.swift LinkService.swift BackgroundLibrary.swift)
for source in "${sources[@]}"; do cp "$project_dir/Sources/SnapDrive/$source" "$test_dir/$source"; done
cp "$project_dir/Tests/DriveLinkChecks.swift" "$test_dir/DriveLinkChecks.swift"
cp "$project_dir/Tests/EditorChecks.swift" "$test_dir/EditorChecks.swift"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" -module-cache-path "${SNAPDRIVE_MODULE_CACHE:-$test_dir/module-cache}" "$test_dir"/*.swift -o "$test_dir/EditorChecks"
"$test_dir/EditorChecks"
