# Build and test

## Requirements

- macOS 13 or later.
- Apple's Xcode Command Line Tools. Install them with `xcode-select --install` if needed.
- A stable code-signing certificate for builds that retain Screen Recording permission across updates.

The app uses native system frameworks. No package manager dependencies are needed for the Mac app.

## Build

Clone the repository and run:

```sh
git clone https://github.com/sanjuantala/sanju-snapdrive.git
cd sanju-snapdrive
SNAPDRIVE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh ./dist
```

The script builds for the current Mac architecture and writes `dist/Sanju's SnapDrive.app`. To build a universal app for Apple silicon and Intel, use:

```sh
SNAPDRIVE_ARCHS="arm64 x86_64" SNAPDRIVE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh ./dist
```

A live Intel hardware test is not claimed.

Use a persistent signing identity. The build script requires an explicit signing choice. Use `SNAPDRIVE_SIGNING_IDENTITY=-` for an ad hoc build, as used by this public package. macOS may require screen capture permission again after an ad hoc update. Use Developer ID signing and notarization for distribution with Apple-verified first launch.

Private Google configuration and signing keys must stay outside the repository. The public download does not contain a private OAuth client secret. Direct uploads need publisher configuration during a source build, described in [Google Drive setup](../GOOGLE_DRIVE_SETUP.md). Saving into a Drive for desktop folder does not need that setup.

## Checks

Run the suites sequentially:

```sh
./scripts/test-all.sh
```

The browser tests use Node.js in addition to Swift. The installer has its own checks:

```sh
./scripts/test-installer.sh
```

Focused checks are available as `scripts/test-interaction.sh`, `test-editor.sh`, `test-image-engine.sh`, `test-icons.sh`, `test-capture.sh`, `test-window.sh`, `test-drive.sh`, `test-browser.sh`, and `test-ui.sh`.

Some checks require a graphical macOS session. Review explicit `SKIP` output rather than treating a skip as a pass. A live capture test is still needed to verify the complete browser-to-editor path.

See [Verification](../VERIFICATION.md) for the recorded release checks and their limits, and [icon attribution](../Resources/Icons/ATTRIBUTION.md) for the included SVG library.
