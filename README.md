# Sanju's SnapDrive

Capture, edit, and save polished screenshots on your Mac. Built with native Swift and AppKit.

**macOS 13 or later.** The universal download supports Apple silicon and Intel Macs. Intel hardware has not been tested live.

## Install

Paste this command into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/sanjuantala/sanju-snapdrive/main/install.sh | bash
```

It installs the app in `~/Applications`. To update, quit SnapDrive and run the same command again.

Prefer a download? Get the app from [Releases](https://github.com/sanjuantala/sanju-snapdrive/releases/latest), or [download the installer](https://github.com/sanjuantala/sanju-snapdrive/releases/latest/download/Sanju-SnapDrive-Installer.zip), unzip it, and double-click **Install.command**.

Open **Sanju's SnapDrive** from your Applications folder. This release is not notarized. macOS may require [first-open approval](https://support.apple.com/en-us/102445), and Screen Recording access may need to be granted again after updates. Allow **Screen Recording** when asked to capture your screen. Opening and editing an existing image does not need that permission.

## What you can do

- Capture a region, window, or display at native Retina resolution.
- Add arrows, text, shapes, circular magnifiers, blur, pixelation, and redactions.
- Style screenshots with backgrounds, padding, corners, shadows, and saved presets.
- Crop, zoom, undo, redo, and clear the canvas without losing local history.
- Export PNG or JPEG, copy an image, or drag it into another app.
- Capture full pages, visible tabs, or selected areas and mark them up in the Chrome/Edge editor.
- Keep everything local by default, or save into a folder synced by Google Drive for desktop. Direct Drive uploads require an advanced [publisher-configured source build](GOOGLE_DRIVE_SETUP.md).

## Browser extension

In the Mac app, choose **Image > Browser Extension...** and follow the setup steps. Capture and edit in the light browser workspace. Adjust a crop before applying it, copy text from a selected area using the Mac connection, or continue with **Edit in Mac App**. Press **Option+Shift+X** in Chrome for a quick capture preview. After updating the app, click **Reload** on the extension card.

See the [extension guide](BrowserExtension/README.md) for installation, full-page limits, and troubleshooting.

## Handy shortcuts

| Action | Shortcut |
| --- | --- |
| Open or paste an image | Cmd+O / Cmd+V |
| Capture a region and copy it on Mac | Ctrl+Option+Cmd+C |
| Select / arrow / text / magnifier | V / A / T / M |
| Zoom in or out | Cmd + / Cmd - |
| Fit / native pixels | Cmd+0 / Cmd+1 |
| Pan the canvas | Space + drag, or Hand (H) |
| Undo / redo | Cmd+Z / Cmd+Shift+Z |
| Export | Cmd+S |
| All shortcuts | Cmd+/ |

Tool keys work while the canvas is focused. Pinch or Cmd/Ctrl-scroll to zoom around the pointer.

## More information

[User guide](docs/USER_GUIDE.md) · [Build and test](docs/DEVELOPMENT.md) · [Verification](VERIFICATION.md) · [Feature comparison](FEATURE_PARITY.md) · [Icon licenses](Resources/Icons/LICENSE.txt)

SnapDrive is independently implemented. It contains no Xnapper source code or artwork. See the verification report for the tested scenarios and remaining limitations.
