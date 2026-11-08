# SnapDrive for Chrome and Edge

Capture a selected area, visible tab, or full page. Add arrows, text, freehand marks, shapes, highlights, and opaque redactions in the light browser editor. Copy or download a PNG, or choose **Edit in Mac App** to send the current image to SnapDrive.

## Install or update

- In the Mac app, choose **Image > Browser Extension…**. This sets up the Mac connection and reveals the included folder.
- In Chrome or Edge, open `chrome://extensions` or `edge://extensions`. Turn on **Developer mode**, choose **Load unpacked**, and select that **BrowserExtension** folder. Pin SnapDrive to the toolbar.
- Already installed? Update the Mac app, then click **Reload** on the extension card. Version 1.6 adds no new browser permissions. You can also load the folder from the separate extension ZIP. Browser capture and editing work without the Mac connection.

## Capture and edit

| Action | How |
| --- | --- |
| Open the capture popup | Click SnapDrive or press **Cmd+Shift+Y** |
| Quick capture of the visible tab | Press **Option+Shift+X** on Mac or **Alt+Shift+X** elsewhere |
| Copy from the quick preview | Click **Copy image** or press **Enter** when it is focused |
| Crop or annotate | Choose a capture mode, then use the browser editor |
| Copy text from a capture | Choose **Copy text**, drag a frame, then click **Read text** and **Copy text** |
| Edit in SnapDrive on Mac | Click **Edit in Mac App** from the preview or editor |
| Recover a recent source capture | Click **Latest capture** in the popup |

Use the settings icon to change full-page quality or manage shortcuts. Chrome can assign a separate shortcut for Selected area. Shortcuts may need to be set in `chrome://extensions/shortcuts` if they conflict with another extension.

In the editor, **V** selects, **A** draws arrows, **T** adds text, **C** crops, and **H** selects Hand. Hold **Space** and drag to pan without changing tools. Tooltips list more keys. Click a text mark in Text mode to edit it. **Esc** cancels a text draft, and clicking outside saves it. **Cmd/Ctrl+Z** undoes an edit. Copy, download, and Mac handoff flatten markup into the exported PNG at native resolution. Save before closing the editor; **Latest capture** opens the original image.

**Crop** does not change the image until you choose **Apply crop** or press Enter. Drag a corner or edge, move the frame from inside, or enter left, top, right, and bottom insets in pixels. Arrow keys move the frame by one pixel; hold Shift for ten. Esc cancels the selection.

**Copy text** needs SnapDrive 1.6 or later connected on Mac. Only the selected pixels are passed to Apple's local text recognition, with visible redactions applied. Review the result and click **Copy text** to paste it elsewhere. If no text is found, the clipboard is left alone.

## Full-page tips

Keep the captured tab active. SnapDrive handles normal scrolling documents and one large visible scrolling panel, waits briefly for lazy content, avoids repeated fixed and sticky elements, and restores scroll position and modified styles. Protected pages may block Full page and Selected area; try **Visible tab**. Cross-origin frames, infinite feeds, and virtualized lists may not capture completely.

Captures are limited to 40 million pixels, 32,768 pixels on a side, 40 MB of PNG data, and 80 tiles. For a very long page, choose **1× smaller** under capture settings or capture an area.

## Where screenshots go

Captures stay in the browser on this device. The extension uses `activeTab`, `scripting`, and `nativeMessaging` and has no blanket access to websites. Its local capture cache holds up to five PNGs or 80 MB, and removes expired entries after 30 minutes on the next access. The Mac helper receives an image only when you choose **Edit in Mac App** or **Read text**. Text recognition does not open the app or save the selected pixels. It is separate from the browser cache. The extension has no upload feature or Google credentials.

If the Mac connection is missing or the app has moved, choose **Image > Browser Extension…** in the Mac app again.

## Development

Run `scripts/test-browser.sh` from the source tree. Tests cover capture pixels and cleanup, layout changes, shortcut routing, editor geometry, clipboard export, and the native connection. The capture workflow was informed by [Awesome Screenshot](https://support.awesomescreenshot.com/hc/en-us/articles/900006317863-How-to-take-a-screenshot-with-the-Awesomescreenshot-extension-add-on) and long-page crop behavior by [GoFullPage](https://blog.gofullpage.com/2021/06/09/improved-cropping-is-here/), and contextual styling by [Shottr](https://shottr.cc/kb/startguide). The UI and SVG icons are original to SnapDrive.
