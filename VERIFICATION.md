# Version 1.5.0 verification

## Public GitHub package

The public package contains no personal Google app configuration or private OAuth credential. Drive folder saving remains available; direct sign-in requires a separately configured build. The app and browser helper are built for both arm64 and x86_64. The live checks below were run on Apple silicon; Intel execution has not been tested on hardware.

The install command and downloadable installer use the published universal archive, verify its SHA-256 checksum and code signature, and install into the current user's Applications folder. They do not disable macOS security checks or clear quarantine attributes. The public app is ad hoc signed for integrity and is not notarized by Apple. All 25 installer tests passed. The real universal archive installed and updated successfully in an isolated home, preserving the previous app for rollback. The certificate-pinned identity checks below apply to the earlier local build.

## Existing app behavior checks

All check suites for the 1.5.0 editor completed successfully; one hosted-view accessibility action fixture explicitly skipped as described below.

## Automated checks

- **287 native interaction checks passed** against the real canvas/document implementation in isolated NSWindows: all eleven tool letter shortcuts, numeric shortcuts, normal typing inside text fields, text focus and outside-click commit, selection, keyboard deletion, movement/resizing, gesture Undo/Redo, drawing/privacy tools, crop, magnifier, copy feedback, and zoom coordinates/keyboard/mouse behavior.
- **Saved defaults passed:** 20 px remains the default after selecting an older 5 px arrow, deselection, tool changes, active drawing, Undo, history restore, opening another image, and a new model after relaunch. Explicit font, color, and magnifier zoom also persist. V/1 preserve selection for immediate handles and Delete.
- **Clear screenshot passed:** empty and annotated documents, active text, feedback, source/history preservation, Undo/Redo through an empty canvas, earlier edits, new imports, and pending-import cancellation. Ordinary annotation Undo preserves a later filename or completed-upload context. The separate Clear annotations action retains the screenshot.
- **Arrow and magnifier pixels passed:** shared arrow draft/export geometry at Fit/native/Retina scales, bounded short/thick arrows, 1–8× circular lenses, edge clipping, safe sampling of redacted/blurred/pixelated content, nonrecursive overlapping lenses, Retina export, and legacy history decoding.
- **23 Lucide 1.68.0 SVG icons passed:** valid 24-point assets, cache reuse, nonempty SVG/native paths, matching footprints, and actual SwiftUI popover-trigger contrast at **1× and 2×**, including enabled/disabled controls. Capture has a white stroke core; Export, Stroke, and Font controls remain neutral and light. Licenses and attribution are included.
- **400 browser assertions passed:** 29 native protocol/image/framing/cache, 170 geometry/popup, 133 worker orchestration/pixel, and 68 page preparation/restoration assertions. These cover native and fractional density, explicit 1×, horizontal/vertical overlap, region capture, dominant scroll panels and border-aware cropping, bounded lazy-content warm-up, page growth, tab changes, cancellation, fixed/sticky elements, exact style/scroll restoration, watchdog cleanup, and bitmap release. Separate Chrome/Edge setup checks verify origin allowlists, helper paths, private file modes, repeat setup, and missing-helper errors.
- Import, backgrounds/presets/history, crop/balance, exact PNG Drive-upload bytes, sharing-only retry, 4K preview coalescing, metadata-only history saves, full-resolution export, and native Retina/DPI/detail checks passed.
- Capture permission prompt-once/relaunch/grant recheck, delays/cancellation, clipboard/editor routing, standard window controls, and Drive/OAuth callback and filesystem checks passed.
- **Vision OCR passed** for recognized text and sensitive-email/IP coordinates in the final run. Sensitive-data suggestions remain reviewable suggestions, not an exhaustive guarantee.
- **Three actual SwiftUI layout renders passed** at default **1,240 × 820** and minimum **1,100 × 720** dimensions, including simultaneous Stroke/Font inputs and the magnifier sidebar.

## Live integration

- Chrome is installed and enabled with user approval. A real visible-area **example.com** capture opened in the native app at **3,024 × 1,572** pixels in the preceding release.
- A real 1.5 full-page capture of a local ten-panel test document opened in the native editor at **2,994 × 4,812** pixels. Bitmap checks confirmed the fixed header appears once, the sticky element retains its original position, and the complete footer is included. This verifies the Chrome-to-helper-to-editor path and a static scrolling document.
- The final compact popup was checked live: three capture buttons, a Quality selector, and collapsed help. A lazy-loading document then captured successfully at **2,994 × 5,132** pixels and opened in the Mac app; visual inspection confirmed all ten original sections, the inserted lazy panel, the complete footer, one fixed header, and the sticky element at its original position.
- A real main-scroll-panel capture also opened at **2,458 × 4,700** pixels. Visual inspection confirmed all ten sections, one sticky element at its original position, and the complete footer; the surrounding sidebar and panel border were excluded as intended.
- In the final running app, clicking **Clear screenshot** returned to the welcome canvas with **“Canvas cleared. Undo to restore your screenshot.”**; **⌘Z** then restored the same 2,458 × 4,700 source. Automatic uploads remained off. The final editor screenshot also confirmed light Capture/Stroke/Export chevrons and icons, default Arrow, a readable app title, and the grouped inspector.
- A final live Selected area check produced an exact **400 × 100 native-pixel PNG** from the chosen on-screen rectangle and opened that source in the editor. The frozen capture contained the expected header and following section, without the selection overlay. A separate live selection was cancelled with **Escape**; its overlay disappeared and the page was restored. Automatic uploads remained off.
- Automatic uploads were turned **off** in the running app. New images remain local unless automatic sending is explicitly enabled or the user chooses Upload/Save to Drive.
- The live app retained **20 px** through a complete quit, signed update, and relaunch. Earlier live checks verified main-display capture at native **2× density**, file import, real OCR, Google sign-in, unchanged exported-image upload, and an anyone-with-link viewer URL for the configured account.
- The app and native helper build and pass deep signature verification while retaining the existing certificate-pinned app identity. Public Google sign-in remains deferred; the configured Google project is still in Testing.

## Limits of this verification

- The standalone SwiftUI accessibility action fixture exposes no child controls in its hosted window and explicitly reports **SKIP**. Native event/model tests and rendered-layout checks run separately. This skip is not counted as a passed action test.
- Static, lazy-growth, and main-scroll-panel full-page captures passed the live checks above. Selected-area capture and Escape cancellation also passed the final live checks above; arbitrary pages and screen densities remain outside this small live sample. Edge uses the same package but was not installed or live-tested. Safari is not included.
- Region/window picker use, multi-display capture, global shortcut activation, and real network interruption recovery remain outside live verified coverage.
- A prior 1.4 idle sample showed **0% CPU** and approximately **67 MB physical footprint**, with a 185 MB peak at that point. This is historical measurement, not a 1.5 editing or worst-case memory guarantee. Bounded previews, caches, history, and browser captures have regression coverage.
- Earlier standalone Vision runs could not initialize (`nilError`); the final 1.5 OCR fixture passed. Exhaustive sensitive-data detection is not claimed.
- The supplied Xnapper disk image passed checksum verification but could not be mounted, so exact original UI/behavior comparison was unavailable. Incoming macOS Share integration, menu-bar file drops, custom font/arrowhead selectors, and automatic app updates remain outside this build. The local app is not notarized for public distribution.

No test suite establishes every possible UI state. These are the scenarios actually checked.
