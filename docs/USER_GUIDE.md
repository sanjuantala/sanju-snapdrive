# User guide

## Capture or open an image

Click **Capture region**, or use its menu for window and display capture. During interactive capture, press **Space** to switch between region and window selection, or **Esc** to cancel. Capture keeps the original screenshot pixels and Retina density.

You can also open an image with **Cmd+O**, drop one into the window, or paste with **Cmd+V**. **Cmd+Shift+V** pastes an image even while a text field is active.

For capture permission, open **System Settings > Privacy & Security > Screen Recording**. On newer macOS versions this is called **Screen & System Audio Recording**. Reopen the app if macOS asks. You do not need screen permission to edit existing images.

Closing the editor leaves the app in the menu bar. Choose **Quit Sanju's SnapDrive** to exit completely.

## Annotate

Every new image starts with **Arrow** selected. Drag to draw, then drag again to add more. Hold **Shift** for 45-degree angle steps. Press **V** to select and adjust an annotation.

Click **Text**, click the image, and type. Clicking outside or changing tools saves the text. **Return** saves, **Option+Return** adds a line, and **Esc** cancels the draft. Double-click existing text to edit it.

**Delete** removes the selected annotation while the canvas is focused. Arrow keys move a selection one native pixel; **Shift** moves it ten pixels. Undo and redo work with **Cmd+Z** and **Cmd+Shift+Z**.

Stroke accepts **0.5-1,000 native pixels** and font size accepts **8-512**. Type a custom value or drag the control label. Explicit drawing defaults persist; selecting an older annotation shows that object's own settings.

**Magnifier** adds a circular 1-8x zoom lens. Click to place it or drag to size it, then use Select to move or resize it. Lenses preserve privacy edits beneath them.

**Clear screenshot** empties the current canvas. Undo restores the screenshot and its edits. Use the Clear menu's **Clear annotations only** option to keep the source image.

## Style and inspect

Choose an image, gradient, solid color, transparent background, custom image, or wallpaper. Adjust padding, inset, corners, shadows, ratio, filename, and watermark. Save the appearance as a preset to reuse it.

Pinch, use **Cmd/Ctrl-scroll**, or press **Cmd + / Cmd -** to zoom. **Cmd+0** fits the image and **Cmd+1** shows native pixels. The zoom control also accepts a custom percentage. Preview scaling does not change export resolution.

Use the **Text Select** tool to recognize a chosen region. The recognized-text panel lets you copy individual lines or all text. Sensitive-data detection suggests redactions for supported patterns. Review the suggestions before sharing.

## Export and local history

Use **Cmd+S** to export, **Cmd+C** to copy the edited image outside text fields, or drag **Drag image out** from the status bar into another app. **Cmd+Shift+C** copies the image even while a text field is active.

Choose **PNG** for lossless output, or JPEG with the desired quality. Native resolution keeps the screenshot's original detail; 2x enlarges the output.

Captures and imports stay local by default. The latest 100 source images, edits, styles, and saved upload links are kept under `~/Library/Application Support/SnapDrive`.

History retains editable source images, including pixels covered by annotation redactions. Exported redactions are flattened into the output. **History > Clear local history** removes stored history, but does not remove existing Drive files or pending uploads.

## Optional Google Drive

You can save into a local folder synced by Google Drive for desktop. This works without configuring a Google app connection. Direct **Upload & copy link** requires an advanced publisher-configured source build; the public download has no private OAuth configuration or in-app configuration importer. See [Google Drive setup](../GOOGLE_DRIVE_SETUP.md).

**Automatic uploads** is off by default. Leave it off to edit locally, then explicitly upload the final screenshot. If you enable it, every new image is sent immediately. Pending uploads require an explicit retry after restart.

## Browser capture

Choose **Image > Browser Extension...** to connect the included Chrome/Edge extension. It can capture a full page, visible area, or selected area and open the result in the native editor.

See the [extension guide](../BrowserExtension/README.md) for setup, native resolution, full-page limits, cancellation, and recovery.

## Shortcuts and help

Open **View > Keyboard Shortcuts...** with **Cmd+/** to see every shortcut and your current global capture bindings. Customize capture bindings in the app settings.

For tested behavior and known limits, see [Verification](../VERIFICATION.md). For source builds, see [Development](DEVELOPMENT.md).
