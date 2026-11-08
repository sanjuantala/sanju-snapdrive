# Feature comparison and verification

This report includes historical checks of the local build. The public GitHub release has no preconfigured Google OAuth connection and uses an ad hoc signature.

Reference: Xnapper macOS 1.18.1, checked 3 November 2026. SnapDrive uses independently written code and original artwork. This comparison tracks behavior and verification, not exact visual or behavioral identity.

## Reference

The supplied `Xnapper-1.18.1-71.dmg` passed `hdiutil verify`, including its overall checksum. Read-only mounting failed with “Device not configured”; installed dialogs and behavior could not be compared directly.

The baseline uses Xnapper's official [homepage](https://xnapper.com/), [macOS changelog](https://xnapper.com/changelog), and [annotation guide](https://xnapper.com/blog/annotate-screenshot). Web-only device mockups are excluded. Delayed capture, preview zoom, and Google Drive workflows are included as SnapDrive enhancements rather than claims about Xnapper's macOS feature set.

| Feature | SnapDrive implementation | Verification |
| --- | --- | --- |
| Region/window capture | Native macOS picker; Space switches selection mode | Code builds; live capture and multiple displays unverified |
| Main-display capture | Native full-screen PNG capture | Live main-display capture passed at native 2× density |
| Configurable global shortcuts | Persistent bindings with collision reporting | Code builds; live shortcut recording unverified |
| Screen permission recovery | Access preflight, one persistent request and stable certificate-pinned identity, Settings link | Stale entry replaced; grant/restart and full-screen capture passed |
| Capture-and-copy | Current-style PNG callback without reopening a closed editor | Offline editor/clipboard routing checks passed |
| Delayed capture | 0/3/5/10-second countdown and cancellation | Preference validation/persistence checked; live countdown-to-picker unverified |
| Native Retina quality | Original native bitmap/DPI retained; PNG export/upload | 2× fixture and one-pixel-detail checks passed |
| Content balance | Uniform-margin trimming; automatic on capture by default | Offline balance and redaction-preservation checks passed; algorithm differs from Xnapper |
| Background matching/window styling | Optional automatic color matching and window framing | Implemented; live window capture unverified |
| Background library | Nine original images, six gradients, custom color/image, wallpaper, transparency | Three photographic scenes at 1,586×992; six procedural designs at 3,840×2,400; offline rendering checked |
| Image-background controls | Independent blur and brightness | Offline rendering checked |
| Padding/inset/corners/shadow | Adjustable values and appearance presets | Offline rendering and style-restoration checks passed |
| Arrows/text/shapes | Default continuous Arrow; shared rounded draft/export geometry; draw, select, move, resize; text/style editing | Native event/pixel checks passed, including Shift angle snapping; custom fonts/arrowhead selectors absent |
| Circular magnifier | Click or drag to place; move/resize, 1–8× zoom and editable border | Native interaction and pixel tests passed, including filtered/redacted content safety |
| Browser extension | Compact Chrome/Edge panel; Full page, Visible area, frozen Selected area; native PNG handoff to Mac editor | 400 browser assertions and setup checks passed; real static 2,994×4,812, lazy-loading 2,994×5,132, and panel 2,458×4,700 imports passed; Edge and final region selection not live-tested |
| Full-page resilience | Main document or large main scroll panel; bounded lazy-content warm-up; one size-change retry; fixed/sticky treatment; restoration | Deterministic geometry/worker/page pixel checks passed; virtualized lists, infinite feeds, and nested/cross-origin frames are not expanded |
| Saved drawing defaults / Clear | Persistent width/color/font/zoom; Clear screenshot and separate Clear annotations, both undoable | 20 px retained across selection, tools, drag, history, next image and relaunch; empty-canvas/history/source/active-text/pending-import Undo/Redo checks passed |
| Redaction/pixelation/blur | Editable annotations flattened into exported pixels | Offline redaction, overlap, and blur checks passed; full live interaction unverified |
| Sensitive-data suggestions | Local Vision plus supported email/IP/card/key patterns | Implemented; real native-app OCR passed; sensitive-data detection is not exhaustive |
| Text selection/OCR | Drag image region for OCR; recognized-text panel with per-line/all-text copy | Implemented; real native-app OCR passed |
| History | Latest 100 local source images, edits, backgrounds, upload links | Offline save/restore and background checks passed |
| Presets/ratios/compression | Saved styles, seven ratios, PNG/JPEG, quality and export scale | Offline persistence, ratio, scale and encoding checks passed |
| Pixel inspection | Fit, 10–400% custom zoom, pinch, pointer-anchored ⌘/Ctrl-scroll and keyboard zoom | Native interaction/coordinate checks passed; gesture rendering uses bounded preview then settled detail |
| Keyboard access | Eleven tool letters, Delete/nudge, ⌘/Ctrl zoom, native menu commands and shortcut help | 287 native interaction checks include canvas shortcuts and normal text-field typing |
| Toolbar and inspector | Consistent light Lucide SVG paths, popover controls, grouped inspector cards | 23 icon assets, actual enabled/disabled 1×/2× contrast, and three default/minimum-width layout renders passed |
| Image input | File, clipboard, editor drag/drop, app open-file handling | Native file import and image-background selection visually verified; clipboard/drop workflows unverified |
| Save/copy/drag export | Local export, PNG clipboard, drag-out status chip | Encoding checked; drag-out and dialogs unverified |
| Filename/watermark | Editable export name, timestamp, optional watermark | Implemented; dedicated default capture-name preference absent |
| Drive folder save | User-selected local folder; Drive for desktop syncs | Offline save/collision/filename checks passed; cloud sync external |
| Direct Drive upload/link | Desktop OAuth/PKCE, Keychain, unchanged exported bytes, Google's viewer URL | Mocked checks and earlier real configured-account sign-in/upload/link passed; Google project remains Testing and public account availability is deferred |
| Local-first captures | Local history by default; optional Automatic uploads toggle; manual Upload/Save to Drive | Current app toggle confirmed off; upload guard/retry/export integration checked |
| Link permissions and history | Anyone-with-link read access or existing access; saved viewer URL | Mocked publication/failure handling checked; live Workspace policy unverified |
| Durable upload queue | Export/sharing snapshot retained; manual retry after failure or restart | Implemented; offline behavior checked; real network recovery unverified |
| Incoming macOS Share extension | Not implemented | Remaining gap |
| Drop onto menu-bar icon | Not implemented | Remaining gap |
| Automatic app updates | Not implemented | Remaining gap |
| Exact original interface/artwork | Independent interface and original backgrounds | No exact-parity claim |

## Checks and remaining verification

Capture checks use a temporary PNG and an isolated preferences suite. They verify pixel dimensions, logical DPI, single-pixel detail after deleting the temporary file, delay settings, and separate clipboard/editor callbacks. They never request screen access or capture the desktop.

Image-engine and editor checks cover pixel orientation, crop, redaction flattening, overlapping edits, blur, ratios, scale, encoding, input bounds, undo/redo, presets, custom backgrounds, and history restoration. Drive checks use local folders and mocked network replies. Real OAuth sign-in, Drive upload/public access, and main-display screen capture passed. Region/window selection and multi-display behavior remain unverified.

The final 1.5 Vision OCR fixture passed; earlier runs reported `nilError`, and real OCR was also verified in the native app. Exhaustive sensitive-data detection remains outside the claim. Version 1.5 passed 287 native interaction checks, 400 browser assertions, and three actual-view layout renders. The separate hosted SwiftUI accessibility action fixture explicitly skipped because it exposed no child controls; it is not counted as a passed action test. See [verification](VERIFICATION.md) for the exact live scope.

Google's original viewer URL is preserved, including resource-key parameters. A separate branded or third-party short-link service is not included. The app has no incoming Share extension, menu-bar drag import, custom font/arrowhead selectors, or automatic software updater.

## Defaults

Capture: region **⌃⌥⌘4**, window **⌃⌥⌘5**, main display **⌃⌥⌘3**. Timer: **off**. Automatic balancing: **on**. Automatic background matching/window framing: **off**. Automatic uploads: **off**, with captures kept in local history; explicit Upload/Save to Drive sends them when ready. New-image tool: **Arrow**. Preview zoom: **Fit**. Direct-upload sharing: **Anyone with the link**, selectable before uploading. Temporary capture files are removed after import.

Native UI verification: loaded a local sample through the asynchronous file picker, selected Dawn Dunes, inspected the rendered preview and background library, and opened the upload setup sheet showing Anyone-with-link access. Mocked editor integration also confirms exact exported PNG bytes are uploaded, upload metadata is durable before sharing begins, sharing failures preserve the file, and changing upload defaults cannot alter an older retry policy.

Version 1.2: Mac app renamed Sanju's SnapDrive; native event handling replaces SwiftUI canvas gestures. 176 native interaction cases pass, including inline text and deletion. Google sign-in is configured in the app and real token exchange succeeded. End users do not create API credentials. Current Google publishing status is Testing. See VERIFICATION.md for exact tested scope and remaining limits.

Version 1.2.1: stable certificate signing, prompt-loop prevention, single attached image picker, asynchronous coordinated file reads with local fallback, and standard native window controls without duplicates. Import failure/preservation and window action checks passed. See VERIFICATION.md for exact scope.

Version 1.3.0: 176 native interaction checks pass. Original vector toolbar icons, custom numeric stroke/font/appearance inputs, reliable outside-click text commit, copy feedback, bounded asynchronous previews, metadata-only edit saves, native-quality exports, and preview/import race protections were implemented and checked. See VERIFICATION.md for exact scope.

Version 1.4.0: redesigned capture header and inspector cards, saved drawing defaults, drag-adjustable numeric controls, Clear/Undo, circular magnifier, and Chrome/Edge extension. 220 native interaction checks passed. Default/minimum-width own-view layout renders passed, and Chrome-to-native-app capture was verified live.

Version 1.5.0: local-first capture behavior, continuous default Arrow with shared draft/export geometry, Clear screenshot plus Undo and separate annotation clearing, pointer/keyboard zoom, shortcut help, Lucide icons with tested light contrast, and a compact three-mode browser extension. Full-page capture supports a large main scroll panel, bounded lazy-content warm-up and one size-change retry. The static full-page Chrome handoff passed live; lazy-loading full-page capture also passed live at 2,994×5,132; main-scroll-panel capture passed live at 2,458×4,700. See [verification](VERIFICATION.md) for limits.
