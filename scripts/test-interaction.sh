#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/snapdrive-interaction.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
sources=(ImageEngine EditorModel ImageImportService EditorCanvas EditorInteraction UIState DriveService GoogleAppConfiguration LinkService BackgroundLibrary)
for source in "${sources[@]}"; do cp "$project_dir/Sources/SnapDrive/$source.swift" "$test_dir/"; done
cp "$project_dir/Tests/InteractionChecks.swift" "$test_dir/"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" -module-cache-path "${SNAPDRIVE_MODULE_CACHE:-$test_dir/module-cache}" "$test_dir"/*.swift -o "$test_dir/InteractionChecks"
"$test_dir/InteractionChecks"
