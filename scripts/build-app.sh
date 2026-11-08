#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output_dir="${1:-$(dirname "$project_dir")}"
build_dir="${SNAPDRIVE_BUILD_DIR:-$project_dir/.build/native}"
mkdir -p "$build_dir/module-cache" "$output_dir"
app_dir="$output_dir/Sanju's SnapDrive.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Helpers"
read -r -a architectures <<< "${SNAPDRIVE_ARCHS:-$(uname -m)}"
if [[ ${#architectures[@]} -eq 0 ]]; then printf 'Choose arm64, x86_64, or both in SNAPDRIVE_ARCHS.\n' >&2; exit 1; fi
app_binaries=()
helper_binaries=()
for target_arch in "${architectures[@]}"; do
  case "$target_arch" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$target_arch" >&2; exit 1 ;; esac
  architecture_dir="$build_dir/$target_arch"
  mkdir -p "$architecture_dir"
  xcrun swiftc -parse-as-library -swift-version 5 -D SNAPDRIVE_BUNDLED_ASSETS -O \
    -target "${target_arch}-apple-macos13.0" -module-cache-path "${SNAPDRIVE_MODULE_CACHE:-$build_dir/module-cache}" \
    "$project_dir"/Sources/SnapDrive/*.swift -o "$architecture_dir/SnapDrive"
  xcrun swiftc -swift-version 5 -O \
    -target "${target_arch}-apple-macos13.0" -module-cache-path "${SNAPDRIVE_MODULE_CACHE:-$build_dir/module-cache}" \
    "$project_dir/Sources/BrowserHost/BrowserHostCore.swift" "$project_dir/Sources/BrowserHost/main.swift" \
    -o "$architecture_dir/SnapDriveBrowserHost"
  app_binaries+=("$architecture_dir/SnapDrive")
  helper_binaries+=("$architecture_dir/SnapDriveBrowserHost")
done
if [[ ${#architectures[@]} -gt 1 ]]; then
  xcrun lipo -create "${app_binaries[@]}" -output "$app_dir/Contents/MacOS/SnapDrive"
  xcrun lipo -create "${helper_binaries[@]}" -output "$app_dir/Contents/Helpers/SnapDriveBrowserHost"
else
  cp "${app_binaries[0]}" "$app_dir/Contents/MacOS/SnapDrive"
  cp "${helper_binaries[0]}" "$app_dir/Contents/Helpers/SnapDriveBrowserHost"
fi
rm -rf "$app_dir/Contents/Resources/BrowserExtension"
cp -R "$project_dir/BrowserExtension" "$app_dir/Contents/Resources/BrowserExtension"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
if [[ -f "$project_dir/Resources/AppIcon.icns" ]]; then cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"; fi
if [[ -d "$project_dir/Resources/Backgrounds" ]]; then mkdir -p "$app_dir/Contents/Resources/Backgrounds"; cp "$project_dir"/Resources/Backgrounds/*.png "$app_dir/Contents/Resources/Backgrounds/"; fi
if [[ -d "$project_dir/Resources/Icons" ]]; then mkdir -p "$app_dir/Contents/Resources/Icons"; cp "$project_dir"/Resources/Icons/* "$app_dir/Contents/Resources/Icons/"; fi
if [[ -f "$project_dir/Resources/GoogleOAuthClient.plist" ]]; then cp "$project_dir/Resources/GoogleOAuthClient.plist" "$app_dir/Contents/Resources/GoogleOAuthClient.plist"; fi
if [[ -n "${SNAPDRIVE_OAUTH_PRIVATE_PLIST:-}" ]]; then cp "$SNAPDRIVE_OAUTH_PRIVATE_PLIST" "$app_dir/Contents/Resources/GoogleOAuthPrivate.plist"; else rm -f "$app_dir/Contents/Resources/GoogleOAuthPrivate.plist"; fi
if [[ -z "${SNAPDRIVE_SIGNING_IDENTITY:-}" ]]; then
  printf 'Set SNAPDRIVE_SIGNING_IDENTITY to a stable signing certificate. Ad-hoc signing resets Screen Recording access after updates.\n' >&2
  exit 1
fi
sign_options=(--force --sign "$SNAPDRIVE_SIGNING_IDENTITY" --timestamp=none)
if [[ -n "${SNAPDRIVE_SIGNING_KEYCHAIN:-}" ]]; then sign_options+=(--keychain "$SNAPDRIVE_SIGNING_KEYCHAIN"); fi
if [[ -n "${SNAPDRIVE_SIGNING_CERTIFICATE:-}" ]]; then
  sign_options+=(--requirements "=designated => anchor \"$SNAPDRIVE_SIGNING_CERTIFICATE\" and identifier \"com.snapdrive.screenshot\"")
fi
if [[ -n "${SNAPDRIVE_SIGNING_PASSWORD_FILE:-}" && -n "${SNAPDRIVE_SIGNING_KEYCHAIN:-}" ]]; then
  IFS= read -r task_signing_password < "$SNAPDRIVE_SIGNING_PASSWORD_FILE"
  security unlock-keychain -p "$task_signing_password" "$SNAPDRIVE_SIGNING_KEYCHAIN"
  unset task_signing_password
fi
helper_sign_options=(--force --sign "$SNAPDRIVE_SIGNING_IDENTITY" --timestamp=none --identifier "com.snapdrive.browser")
if [[ -n "${SNAPDRIVE_SIGNING_KEYCHAIN:-}" ]]; then helper_sign_options+=(--keychain "$SNAPDRIVE_SIGNING_KEYCHAIN"); fi
if [[ -n "${SNAPDRIVE_SIGNING_CERTIFICATE:-}" ]]; then
  helper_sign_options+=(--requirements "=designated => anchor \"$SNAPDRIVE_SIGNING_CERTIFICATE\" and identifier \"com.snapdrive.browser\"")
fi
codesign "${helper_sign_options[@]}" "$app_dir/Contents/Helpers/SnapDriveBrowserHost"
codesign "${sign_options[@]}" "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf 'Built %s\n' "$app_dir"
