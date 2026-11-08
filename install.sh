#!/bin/bash
set -euo pipefail
umask 077

# Downloads only the published release from sanjuantala/sanju-snapdrive.
install_version="1.5.0"
install_asset="Sanju-SnapDrive-${install_version}-macOS.zip"
install_release="https://github.com/sanjuantala/sanju-snapdrive/releases/download/v${install_version}"
install_app_name="Sanju's SnapDrive.app"
install_bundle_id="com.snapdrive.screenshot"
install_destination="${HOME:?Your home folder is unavailable}/Applications"
install_should_open=1
install_workdir=""
install_stage=""
install_backup=""
install_lock=""
install_target=""
install_new_placed=0
install_committed=0

fail() { printf 'Install stopped: %s\n' "$*" >&2; exit 1; }
usage() {
    printf '%s\n' "Install Sanju's SnapDrive ${install_version}" \
        'Usage: bash install.sh [--no-open] [--destination /absolute/folder]' \
        'Default destination: ~/Applications. No administrator password needed.'
}
cleanup() {
    local result=$?
    trap - EXIT INT TERM
    if [[ "$install_committed" -eq 0 && "$install_new_placed" -eq 1 && -d "$install_target" && ! -L "$install_target" ]]; then
        mv "$install_target" "$install_stage/failed.app" 2>/dev/null || true
    fi
    if [[ "$install_committed" -eq 0 && -n "$install_backup" && -d "$install_backup/$install_app_name" ]]; then
        if [[ ! -e "$install_target" && ! -L "$install_target" ]]; then
            if mv "$install_backup/$install_app_name" "$install_target"; then
                printf 'Your previous app was restored.\n' >&2
            else
                printf 'Your previous app is safe at: %s\n' "$install_backup/$install_app_name" >&2
            fi
        else
            printf 'Your previous app is safe at: %s\n' "$install_backup/$install_app_name" >&2
        fi
    fi
    [[ -z "$install_workdir" ]] || rm -rf "$install_workdir"
    [[ -z "$install_stage" ]] || rm -rf "$install_stage"
    [[ -z "$install_backup" ]] || rmdir "$install_backup" 2>/dev/null || true
    [[ -z "$install_lock" ]] || rmdir "$install_lock" 2>/dev/null || true
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --no-open) install_should_open=0 ;;
        --destination)
            [[ $# -gt 1 && -n "$2" ]] || fail '--destination needs an absolute folder path.'
            install_destination="$2"; shift ;;
        *) fail "Unknown option: $1. Use --help." ;;
    esac
    shift
done

[[ "$(uname -s)" == Darwin ]] || fail 'This app needs macOS 13 or newer.'
install_arch="$(uname -m)"
case "$install_arch" in arm64|x86_64) ;; *) fail "Unsupported Mac architecture: $install_arch." ;; esac
install_os_version="$(sw_vers -productVersion)"
install_os_major="${install_os_version%%.*}"
[[ "$install_os_major" =~ ^[0-9]+$ && "$install_os_major" -ge 13 ]] || fail 'This app needs macOS 13 or newer.'
case "$install_destination" in /*) ;; *) fail 'The destination must be an absolute folder path.' ;; esac
case "/$install_destination/" in */../*|*/./*) fail 'Use a destination without . or .. path segments.' ;; esac
[[ "$install_destination" != *$'\n'* && "$install_destination" != *$'\r'* ]] || fail 'The destination contains an unsupported line break.'
install_destination="${install_destination%/}"
[[ -n "$install_destination" ]] || fail 'Choose an Applications folder, not the filesystem root.'
install_check_path="$install_destination"
while [[ "$install_check_path" != / ]]; do
    [[ ! -L "$install_check_path" ]] || fail "The destination contains a symbolic link: $install_check_path. Choose a regular folder."
    [[ ! -e "$install_check_path" || -d "$install_check_path" ]] || fail "The destination contains a file: $install_check_path."
    install_check_path="$(dirname "$install_check_path")"
done
for install_tool in curl shasum ditto codesign file zipinfo pgrep; do
    command -v "$install_tool" >/dev/null 2>&1 || fail "Missing macOS tool: $install_tool."
done
if pgrep -u "$(id -u)" -x SnapDrive >/dev/null 2>&1; then
    fail "Quit Sanju's SnapDrive, then run this command again. Your screenshots will stay saved."
fi
install_target="$install_destination/$install_app_name"
if [[ -e "$install_target" || -L "$install_target" ]]; then
    [[ -d "$install_target" && ! -L "$install_target" && ! -L "$install_target/Contents/Info.plist" ]] || fail 'An unexpected file or symbolic link already uses the app name. Move it before installing.'
    install_existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$install_target/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$install_existing_id" == "$install_bundle_id" ]] || fail 'A different app already uses this name. It was left untouched.'
fi

printf "Downloading Sanju's SnapDrive %s...\n" "$install_version"
install_workdir="$(mktemp -d "${TMPDIR:-/tmp}/sanju-snapdrive.XXXXXXXX")"
curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 180 \
    --proto '=https' --tlsv1.2 "$install_release/$install_asset" --output "$install_workdir/$install_asset"
curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 60 \
    --proto '=https' --tlsv1.2 "$install_release/SHA256SUMS" --output "$install_workdir/SHA256SUMS"
install_expected="$(awk -v asset="$install_asset" '$2 == asset || $2 == "*" asset { print $1 }' "$install_workdir/SHA256SUMS")"
[[ "$install_expected" =~ ^[[:xdigit:]]{64}$ ]] || fail 'The release checksum is missing or invalid. Nothing was installed.'
install_actual="$(shasum -a 256 "$install_workdir/$install_asset" | awk '{print $1}')"
install_expected="$(printf '%s' "$install_expected" | tr 'A-F' 'a-f')"
[[ "$install_actual" == "$install_expected" ]] || fail 'The download failed its checksum check. Nothing was installed. Try again.'

# Reject paths that could escape the extraction folder, even in a signed release.
zipinfo -1 "$install_workdir/$install_asset" > "$install_workdir/entries"
while IFS= read -r install_entry; do
    [[ -n "$install_entry" ]] || fail 'The release archive contains an invalid path.'
    case "$install_entry" in /*|*\\*|../*|*/../*|*/..|./*|*/./*) fail 'The release archive contains an unsafe path.' ;; esac
    case "$install_entry" in "$install_app_name"|"$install_app_name/"*|__MACOSX/*) ;; *) fail 'The release archive contains unexpected files.' ;; esac
done < "$install_workdir/entries"
mkdir "$install_workdir/extracted"
ditto -x -k "$install_workdir/$install_asset" "$install_workdir/extracted"
install_source="$install_workdir/extracted/$install_app_name"
[[ -d "$install_source" && ! -L "$install_source" ]] || fail 'The release does not contain the Mac app.'
[[ -z "$(find "$install_source" -type l -print -quit)" ]] || fail 'The release contains unexpected symbolic links.'
[[ -f "$install_source/Contents/Info.plist" && -x "$install_source/Contents/MacOS/SnapDrive" && -x "$install_source/Contents/Helpers/SnapDriveBrowserHost" ]] || fail 'The downloaded app is incomplete.'
install_downloaded_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$install_source/Contents/Info.plist" 2>/dev/null || true)"
install_downloaded_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$install_source/Contents/Info.plist" 2>/dev/null || true)"
[[ "$install_downloaded_id" == "$install_bundle_id" && "$install_downloaded_version" == "$install_version" ]] || fail 'The release app identity or version is incorrect.'
codesign --verify --deep --strict "$install_source" || fail 'The downloaded app failed its signature check.'
supports_arch() {
    file -b "$1" | grep -E "Mach-O.*executable ${install_arch}([^[:alnum:]_]|$)" >/dev/null
}
supports_arch "$install_source/Contents/MacOS/SnapDrive" || fail 'This release does not support your Mac.'
supports_arch "$install_source/Contents/Helpers/SnapDriveBrowserHost" || fail 'The browser helper does not support your Mac.'

mkdir -p "$install_destination"
if ! mkdir "$install_destination/.snapdrive-install.lock" 2>/dev/null; then
    fail "Another installation may be running. If it has stopped, remove $install_destination/.snapdrive-install.lock and try again."
fi
install_lock="$install_destination/.snapdrive-install.lock"
install_stage="$(mktemp -d "$install_destination/.snapdrive-install.XXXXXXXX")"
ditto "$install_source" "$install_stage/$install_app_name"
codesign --verify --deep --strict "$install_stage/$install_app_name" || fail 'The app could not be copied correctly. Your existing app was left untouched.'
if pgrep -u "$(id -u)" -x SnapDrive >/dev/null 2>&1; then
    fail "Quit Sanju's SnapDrive, then run this command again. Your existing app was left untouched."
fi
# Recheck after the download in case another app was placed here meanwhile.
if [[ -e "$install_target" || -L "$install_target" ]]; then
    [[ -d "$install_target" && ! -L "$install_target" && ! -L "$install_target/Contents/Info.plist" ]] || fail 'The destination changed during the download. Nothing was replaced.'
    install_existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$install_target/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$install_existing_id" == "$install_bundle_id" ]] || fail 'The destination changed during the download. Nothing was replaced.'
    install_backup="$(mktemp -d "$install_destination/.snapdrive-backup.XXXXXXXX")"
    mv "$install_target" "$install_backup/$install_app_name"
fi
mv "$install_stage/$install_app_name" "$install_target"
install_new_placed=1
codesign --verify --deep --strict "$install_target" || fail 'The installed app failed verification.'
install_committed=1
printf 'Installed: %s\n' "$install_target"
if [[ -n "$install_backup" ]]; then printf 'Previous app kept for rollback: %s\n' "$install_backup/$install_app_name"; fi
if [[ "$install_should_open" -eq 1 ]]; then
    if /usr/bin/open "$install_target"; then
        printf 'Ready. macOS may ask you to approve the app or allow Screen Recording for capture.\n'
    else
        printf 'Open the app from your Applications folder. macOS may ask for first-launch approval.\n'
    fi
fi
