# Sanju’s SnapDrive browser extension 1.5

Capture a **full page**, **visible area**, or **selected area** in Chrome or Edge. Every capture opens directly in the Mac editor with arrows, text, shapes, blur, pixelation, magnifier, crop, backgrounds, undo, and export. Captures stay local by default; use Upload when you choose to send one to Drive.

## One-time setup

1. Put **Sanju’s SnapDrive.app** in its final location and open it.
2. In its **Image** menu, choose **Browser Extension…**. This installs the local connection, reveals the packaged extension folder, and copies its path.
3. Open `chrome://extensions` in Chrome, or `edge://extensions` in Edge.
4. Enable **Developer mode**, choose **Load unpacked**, and select the revealed **BrowserExtension** folder. Use **⌘⇧G** and paste the copied path in the folder picker.
5. Pin **Sanju’s SnapDrive** in your browser, then click it. **⌘⇧Y** also opens the capture panel, unless another shortcut already uses it.

**Updating from 1.4:** after updating the Mac app, click **Reload** on the extension card. The added `scripting` permission lets Full page and Selected area work on the tab you explicitly invoke. If the browser asks to re-enable the updated extension, approve that permission there.

This development package is ready for local use; it is not published in an extension store. Safari is not included.

## Capture modes

- **Full page** scrolls and stitches the main document vertically and horizontally. For app-style pages whose document fits the window, it can capture the largest fully visible scrolling panel that occupies at least half the viewport. Stay on the captured tab and keep its size and zoom unchanged until complete. The extension popup can close without stopping the capture. Reopen it to see progress or cancel. Existing fixed elements appear once; sticky elements retain their original layout position instead of repeating at tile boundaries.
- **Visible area** transfers the browser’s original lossless PNG bytes unchanged, including their original pixel dimensions.
- **Selected area** freezes the visible screenshot first. Drag a rectangle over that frozen image; **Escape** cancels. The selected native pixels open in the Mac editor.
- **Full-page resolution** defaults to **Native / Retina**, preserving the browser screenshot’s density. Choose **1×** explicitly for a taller page to fit within the same image-size limit. This is an intentional quality choice; captures are never silently reduced to fit.

No browser-side image editor needs separate maintenance or credentials. Captures open in the full Mac editor immediately. Native app local history and export settings apply to browser captures too. Automatic uploads are off by default and can be enabled separately in settings.

## Quality and limits

PNG stitching and cropping are lossless. Native mode copies tile pixels without resizing; endpoint rounding handles fractional browser density and the final overlapping tile. Full-page capture first warms lazy-loaded content with a bounded scroll pass, waits briefly for visible images and fonts, pauses CSS animation, avoids repeated fixed/sticky headers, and restores scroll position and modified styles after success, error, or cancellation. A page-side watchdog restores styles if the worker is unexpectedly interrupted.

Captures are bounded to **40 million output pixels**, **32,768 pixels on either side**, **40 MB PNG**, and **80 viewport tiles**. For example, Retina output uses four times the pixels of 1× at a 2× density. Choose 1× or a selected area for very tall pages. Captures are spaced at least 650 ms apart to stay below Chrome’s two-captures-per-second quota.

Full page handles the main document, including horizontal overflow, or one large visible scrolling panel. Cross-origin frames, virtualized lists, multiple independent panels, and infinite feeds are not expanded into a complete document. If dimensions change during stitching, the partial image is discarded and the extension retries once. Continued changes stop with an explanation. Let the page finish loading, then retry. A maximum of 30,000 page elements are examined for sticky/fixed treatment; extremely complex pages may still have repeated overlays. Video and live canvas content can change between tiles. Protected/internal pages may block injection; try Visible area or the Mac app’s native capture.

Screen/video recording, scrolling inside nested frames or multiple panels, browser-only annotation, PDF exports from the extension, account collaboration, and store publishing are not included in this release.

## Privacy and local connection

- Permissions: `activeTab`, `scripting`, and `nativeMessaging`. No broad host permissions, always-on content scripts, browsing history permission, or external message listener.
- Screenshot and temporary page scripts run only after choosing a capture mode on the active tab. A tab change aborts capture before pixels are handed to the Mac app.
- Pixels pass through a short-lived helper bundled with the app. The extension has no Google credentials and makes no network uploads. The native app keeps captures local by default. It uploads only when you press Upload, unless you explicitly enable Automatic uploads.
- The helper accepts only the packaged extension’s origin, the supported protocol version, and a bounded PNG capture. It accepts no arbitrary file path, executable command, or website URL.
- Handoff files are private to your user in `~/Library/Caches/com.snapdrive.screenshot/Browser Captures`. Cleanup keeps at most 20 captures, limits retained older captures to 200 MB, removes captures over one day old on the next capture, and keeps the new capture for the app’s asynchronous import. This cache is separate from screenshot history.

## Troubleshooting

**“Connect the Mac app first”**: run **Image → Browser Extension…** in the app, then retry. Repeat if you moved or renamed the app.

**Capture blocked**: try a normal website, Visible area, or a native region capture. Your browser may restrict internal or protected pages.

**Image too large**: choose **1×** for Full page or use Selected area. No partial/downsampled result is sent silently.

**Page changed or tab changed**: keep the original tab open, let loading finish, then retry without resizing or zooming.

**Shortcut unavailable**: change it under the browser’s extension keyboard shortcuts.

**Remove the connection**: remove the extension, then delete only `com.snapdrive.browser.json` from `~/Library/Application Support/Google/Chrome/NativeMessagingHosts` and `~/Library/Application Support/Microsoft Edge/NativeMessagingHosts` if present.

## Developer verification

Run `scripts/test-browser.sh` from app source. It checks native PNG byte preservation, framing, malformed requests, cache bounds and file modes; setup allowlists and helper paths; permission scope and stable identity; tile coverage and exact pixels across horizontal/vertical overlap and fractional density; explicit 1×; visible and frozen-region capture; popup duplicate prevention; tab changes, errors and cancellation; lazy-content warm-up, main-panel selection and border-aware cropping, restoration, and bitmap release. Geometry/worker pixel tests use deterministic simulated screenshot tiles; a live browser capture is also required for integration verification.

References: Awesome Screenshot’s official [capture workflow](https://support.awesomescreenshot.com/hc/en-us/articles/900006317863-How-to-take-a-screenshot-with-the-Awesomescreenshot-extension-add-on) and [annotation workflow](https://support.awesomescreenshot.com/hc/en-us/articles/900005735846-How-to-annotate-edit-a-screenshot-with-lines-shapes-arrows-and-more) informed the requested modes. Implementation uses Chrome’s official [native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [Tabs API](https://developer.chrome.com/docs/extensions/reference/api/tabs#method-captureVisibleTab), and [Scripting API](https://developer.chrome.com/docs/extensions/reference/api/scripting) documentation. The public manifest key keeps the local extension ID stable; no private signing key is included.
