import AppKit
import Foundation
import SwiftUI

@main struct EditorChecks {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("SnapDrive-editor-checks-" + UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "SnapDriveChecks." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { try? fm.removeItem(at: dir); preferences.removePersistentDomain(forName: suite) }
        let model = EditorModel(storageDirectory: dir, preferences: preferences)
        let cg = CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.setFillColor(NSColor.white.cgColor); cg.fill(CGRect(x: 0,y: 0,width: 320,height: 240))
        let image = NSImage(cgImage: cg.makeImage()!, size: NSSize(width: 320,height: 240))
        try drawingPreferencesChecks(storage: dir.appendingPathComponent("drawing-preferences"), image: image)
        try await clearCanvasChecks(storage: dir.appendingPathComponent("clear-canvas"), image: image)
        try await importChecks(storage: dir.appendingPathComponent("import-checks"), preferences: preferences, image: image)
        model.load(image, name: "Fixture")
        assert(model.history.count == 1 && model.preview != nil)
        let redact = Annotation(kind: .redact,start: CGPoint(x: 0.2,y: 0.2),end: CGPoint(x: 0.4,y: 0.4),colorHex: "#000000")
        model.add(redact); model.balance()
        assert(model.annotations.isEmpty)
        let flattened = NSBitmapImageRep(cgImage: ImageEngine.cgImage(model.image!)!)
        assert(flattened.colorAt(x: flattened.pixelsWide/2,y: flattened.pixelsHigh/2)!.redComponent < 0.05, "Balancing must keep redacted pixels hidden")
        model.undo(); assert(model.annotations.count == 1, "Undo restores editable layers")
        model.redo(); assert(model.annotations.isEmpty)
        model.undo(); model.crop(CGRect(x: 0,y: 0,width: 0.5,height: 0.5))
        assert(ImageEngine.pixelSize(model.image!).width == 160)
        model.undo(); assert(ImageEngine.pixelSize(model.image!).width == 320 && model.annotations.count == 1)
        model.checkpoint(); model.backgroundImage = image; model.style.background = "custom"
        model.undo(); assert(model.backgroundImage == nil, "Undo must restore the background image too")
        model.redo(); assert(model.backgroundImage != nil)
        model.savePreset("Fixture style"); let preset = model.presets[0]
        model.backgroundImage = nil; model.style.background = "ocean"; model.applyPreset(preset)
        assert(model.style.background == "custom" && model.backgroundImage != nil)
        model.persistCurrent()
        let restored = EditorModel(storageDirectory: dir, preferences: preferences)
        assert(restored.history.count == 1)
        restored.restore(restored.history[0])
        assert(restored.annotations.count == 1 && restored.backgroundImage != nil)
        guard let (data, name) = restored.output() else { fatalError("Export unavailable") }
        assert(!data.isEmpty && name.hasSuffix(".png"))
        try await uploadIntegration(storage: dir.appendingPathComponent("upload-fixture"), preferences: preferences, image: image)
        try await performanceChecks(storage: dir.appendingPathComponent("performance"), preferences: preferences)
        print("PASS editor import, redaction-preserving balance, crop, undo/redo, background undo, custom preset, history restore, export")
    }
}

extension EditorChecks {
    @MainActor static func drawingPreferencesChecks(storage: URL, image: NSImage) throws {
        let suite = "SnapDriveDrawingChecks." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = EditorModel(storageDirectory: storage, preferences: preferences)
        model.load(image)
        model.setSelectedLineWidth(20)
        model.setSelectedFontSize(42)
        model.setSelectedColor(.blue)
        model.setSelectedMagnification(3)
        let old = Annotation(kind: .arrow, start: CGPoint(x: 0.2,y: 0.2),end: CGPoint(x: 0.5,y: 0.5),lineWidth: 5)
        model.add(old)
        assert(model.lineWidth == 5, "Selecting an old 5 px arrow shows its actual width")
        model.selectAnnotation(nil)
        assert(model.lineWidth == 20 && model.fontSize == 42 && model.ink.hexString == Color.blue.hexString && model.magnification == 3, "Deselect restores the explicitly saved drawing defaults")
        model.selectAnnotation(old.id); model.tool = .rectangle
        assert(model.selectedID == nil && model.lineWidth == 20, "Switching tools must not inherit an old annotation's 5 px stroke")
        model.selectAnnotation(old.id)
        assert(model.beginAnnotationEdit(id: old.id))
        var moved = old; moved.end.x = 0.6
        model.updateAnnotationEdit(moved)
        model.setSelectedLineWidth(20)
        assert(model.annotations[0].lineWidth == 20 && model.lineWidth == 20, "Finishing an active drag cannot overwrite a newly entered stroke width")
        model.undo()
        assert(model.annotations[0].lineWidth == 5 && model.lineWidth == 5)
        model.selectAnnotation(nil)
        assert(model.lineWidth == 20, "Undoing an object's width must not overwrite the saved preference")
        model.persistCurrent()
        let relaunched = EditorModel(storageDirectory: storage, preferences: preferences)
        assert(relaunched.lineWidth == 20 && relaunched.fontSize == 42 && relaunched.magnification == 3)
        relaunched.restore(relaunched.history[0])
        relaunched.selectAnnotation(old.id); relaunched.selectAnnotation(nil)
        assert(relaunched.lineWidth == 20, "Restoring history cannot revert the drawing default")
        relaunched.load(image, name: "Next screenshot")
        assert(relaunched.lineWidth == 20 && relaunched.fontSize == 42, "Opening another screenshot keeps the saved width and font")
        model.redo(); model.selectAnnotation(old.id)
        let beforeClear = model.annotations, beforeUndoCount = model.undoStack.count
        let writes = model.sourceWriteCount
        model.clearAnnotations()
        assert(model.annotations.isEmpty && model.selectedID == nil && model.tool == .select)
        assert(model.undoStack.count == beforeUndoCount + 1 && model.lineWidth == 20)
        model.persistCurrent()
        assert(model.sourceWriteCount == writes, "Clear only changes editable layers; the original screenshot stays intact")
        model.clearAnnotations()
        assert(model.undoStack.count == beforeUndoCount + 1, "Clearing an empty document creates no redundant undo")
        assert(model.toast == "No annotations to clear", "An empty annotation clear still explains the result")
        model.undo(); assert(model.annotations == beforeClear && model.selectedID == old.id)
        model.redo(); assert(model.annotations.isEmpty)
        print("PASS drawing defaults: 20 px retained across selection, tool switch, active drag, undo, history, next image and relaunch; Clear annotations undo/redo preserves source")
    }
    @MainActor static func clearCanvasChecks(storage: URL, image: NSImage) async throws {
        let suite = "SnapDriveClearChecks." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = EditorModel(storageDirectory: storage, preferences: preferences)
        model.clearCanvas()
        assert(model.undoStack.isEmpty && model.toast == "Canvas is already clear")
        model.load(image, name: "Clear fixture")
        assert(model.tool == .arrow, "New screenshots open with Arrow ready to draw")
        model.setSelectedLineWidth(20)
        model.add(Annotation(kind: .arrow, start: CGPoint(x: 0.1,y: 0.2),end: CGPoint(x: 0.5,y: 0.6),lineWidth: 20))
        let id = model.currentHistoryID!, annotations = model.annotations, undoCount = model.undoStack.count
        model.persistCurrent()
        let sourceURL = storage.appendingPathComponent("\(id).png"), source = try Data(contentsOf: sourceURL)
        model.clearCanvas()
        assert(model.image == nil && model.preview == nil && model.annotations.isEmpty && model.selectedID == nil)
        assert(model.currentHistoryID == nil && model.uploadResult == nil && model.lastSavedURL == nil)
        assert(model.fileName == "Screenshot" && model.undoStack.count == undoCount+1 && model.lineWidth == 20)
        assert(model.toast == "Canvas cleared · Undo to restore")
        let keptSource = try Data(contentsOf: sourceURL)
        assert(keptSource == source, "Clearing the workspace keeps the source in history")
        let saved = EditorModel(storageDirectory: storage, preferences: preferences)
        assert(saved.history.count == 1 && saved.history[0].annotations == annotations)
        model.undo()
        assert(model.image != nil && model.annotations == annotations && model.currentHistoryID == id && model.fileName == "Clear fixture")
        model.redo()
        assert(model.image == nil && model.currentHistoryID == nil && model.annotations.isEmpty)
        model.undo(); model.undo()
        assert(model.image != nil && model.annotations.isEmpty, "Earlier annotation undo remains valid after restoring a cleared canvas")
        model.redo(); assert(model.annotations == annotations)
        model.clearCanvas(); let count = model.undoStack.count
        model.clearCanvas(); assert(model.undoStack.count == count)
        model.load(image, name: "New after clear"); model.undo()
        assert(model.image != nil && model.fileName == "New after clear", "New imports discard old document undo snapshots")
        let pendingURL = storage.appendingPathComponent("Pending.png")
        try source.write(to: pendingURL)
        model.open(pendingURL); model.clearCanvas()
        try await Task.sleep(nanoseconds: 100_000_000)
        assert(model.image == nil, "A pending import cannot reopen a canvas the user just cleared")
        model.load(image, name: "Context fixture")
        model.add(Annotation(kind: .rectangle, start: CGPoint(x: 0.1,y: 0.2),end: CGPoint(x: 0.5,y: 0.6)))
        model.fileName = "Renamed export"
        let savedURL = URL(fileURLWithPath: "/tmp/SnapDrive-context-fixture.png")
        model.lastSavedURL = savedURL
        model.undo()
        assert(model.fileName == "Renamed export" && model.lastSavedURL == savedURL, "Undoing an annotation must not revert a later filename or saved-file link")
        model.clearCanvas(); model.undo()
        assert(model.fileName == "Renamed export" && model.lastSavedURL == savedURL, "Undoing Clear restores the screenshot's export context")
        print("PASS Clear screenshot: blank/annotated canvas, feedback, source/history preservation, Undo/Redo from empty, earlier edits, new import and pending-import cancellation")
    }
    @MainActor static func performanceChecks(storage: URL, preferences: UserDefaults) async throws {
        let context = CGContext(data: nil, width: 3840, height: 2160, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let rep = NSBitmapImageRep(cgImage: context.makeImage()!); rep.size = NSSize(width: 1920, height: 1080)
        let image = NSImage(size: rep.size); image.addRepresentation(rep)
        let model = EditorModel(storageDirectory: storage, preferences: preferences)
        model.load(image)
        let writes = model.sourceWriteCount
        let source = storage.appendingPathComponent("\(model.currentHistoryID!).png")
        let initialBytes = try Data(contentsOf: source)
        let initialDate = try FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate] as! Date
        let renders = model.previewRenderCount
        for n in 0..<80 { model.style.padding = Double(n) }
        model.add(Annotation(kind: .rectangle, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.4)))
        for _ in 0..<5 { model.persistCurrent() }
        assert(model.sourceWriteCount == writes, "Style and annotation edits must not re-encode the native source")
        let finalBytes = try Data(contentsOf: source)
        let finalDate = try FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate] as? Date
        assert(finalBytes == initialBytes && finalDate == initialDate)
        try await waitForPreview(model)
        let size = ImageEngine.pixelSize(model.preview!)
        assert(max(size.width, size.height) <= 1800)
        assert(model.previewRenderCount - renders < 10, "Rapid updates coalesce; no queue of 80 obsolete render jobs")
        let expected = ImageEngine.dimensions(image: model.image!, style: model.style)
        assert(ImageEngine.pixelSize(model.renderedOutput()!) == expected, "Full-quality export cannot use the small preview")
        assert(max(ImageEngine.pixelSize(model.thumbnail(model.history[0])!).width, ImageEngine.pixelSize(model.thumbnail(model.history[0])!).height) <= 340)
        model.zoom = 1
        try await waitForPreview(model)
        assert(ImageEngine.pixelSize(model.preview!) == expected, "100% zoom uses original detail")
        model.load(image, name: "Same source, new history")
        assert(model.sourceWriteCount == writes + 1 && FileManager.default.fileExists(atPath: storage.appendingPathComponent("\(model.currentHistoryID!).png").path))
        print("PASS performance: bounded/coalesced 4K previews, unchanged native export and 100% zoom, bounded history thumbnails, metadata-only edit saves, same-image new-history persistence")
    }
    @MainActor static func waitForPreview(_ model: EditorModel) async throws {
        // Allow in-flight coalesced jobs to settle, then confirm the last update was applied.
        for _ in 0..<1000 {
            if model.previewIsCurrent { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        fatalError("Preview rendering did not complete")
    }
    @MainActor static func importChecks(storage: URL, preferences: UserDefaults, image: NSImage) async throws {
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(cgImage: ImageEngine.cgImage(image)!)
        bitmap.size = NSSize(width: 160, height: 120)
        for (format, suffix) in [(NSBitmapImageRep.FileType.png, "PNG"), (.jpeg, "jpg"), (.tiff, "tiff"), (.gif, "gif"), (.bmp, "bmp")] {
            let url = storage.appendingPathComponent("Image with spaces.\(suffix)")
            try bitmap.representation(using: format, properties: [:])!.write(to: url)
            let loaded = try ImageImportService.decode(url)
            assert(ImageEngine.pixelSize(loaded) == CGSize(width: 320, height: 240), "Native image pixels must survive import")
            if format == .png { assert(abs(loaded.size.width - 160) < 0.1, "Retina density must survive import") }
        }
        let first = storage.appendingPathComponent("First.PNG"), second = storage.appendingPathComponent("Second.PNG")
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: first); try png.write(to: second)
        let model = EditorModel(storageDirectory: storage.appendingPathComponent("history"), preferences: preferences)
        model.open(first); model.open(second)
        for _ in 0..<500 { if model.image != nil { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        assert(model.fileName == "Second" && model.history.count == 1, "Latest open wins; cancelled imports must not create history")
        let original = model.image
        for bad in [storage.appendingPathComponent("missing.png"), storage.appendingPathComponent("broken.png")] {
            if bad.lastPathComponent == "broken.png" { try Data("invalid image".utf8).write(to: bad) }
            model.error = nil; model.open(bad)
            for _ in 0..<500 { if model.error != nil { break }; try await Task.sleep(nanoseconds: 10_000_000) }
            assert(model.error != nil && model.image === original && model.history.count == 1, "Failed imports preserve current document")
        }
        model.open(first); model.load(image, name: "Newer pasted image")
        try await Task.sleep(nanoseconds: 100_000_000)
        assert(model.fileName == "Newer pasted image" && model.history.count == 2, "A pending file import cannot replace a newer paste or capture")
        let previous = model.history[1]
        model.open(first); model.restore(previous)
        try await Task.sleep(nanoseconds: 100_000_000)
        assert(model.currentHistoryID == previous.id && model.fileName == "Second" && model.history.count == 2, "A pending file import cannot replace a history selection")
        print("PASS image import: PNG/JPEG/TIFF/GIF/BMP, uppercase/spaced paths, Retina DPI, latest request wins, missing/corrupt errors preserve document")
    }
    @MainActor static func uploadIntegration(storage: URL, preferences: UserDefaults, image: NSImage) async throws {
        var copied: [String] = []
        let model = EditorModel(storageDirectory: storage, preferences: preferences, clipboardWriter: { copied.append($0) })
        model.load(image, name: "Retina fixture")
        model.style.padding = 0; model.style.radius = 0; model.style.shadow = 0; model.style.background = "transparent"; model.style.exportScale = 1
        let expected = model.output()!.0
        let encoded = NSBitmapImageRep(data: expected)!
        assert(encoded.pixelsWide == 320 && encoded.pixelsHigh == 240)
        var permissionFails = true
        try await DriveLinkChecks.withService { service, trace in
            trace.responder = { request in
                if request.url?.path.hasSuffix("/permissions") == true {
                    if trace.uploadTransfers == 1 && trace.permissionRequests.count == 1 {
                        let disk = try JSONSerialization.jsonObject(with: Data(contentsOf: storage.appendingPathComponent("pending-uploads.json"))) as! [[String: Any]]
                        assert((disk.first?["uploaded"] as? [String: Any])?["fileID"] as? String == "file_fixture", "Uploaded metadata must be durable before permission publication begins")
                    }
                    return permissionFails ? .json(["error": ["message": "Fixture policy refused sharing"]], status: 403) : .json(["id": "permission-fixture", "type": "anyone", "role": "reader"])
                }
                if request.httpMethod == "GET" { return DriveLinkChecks.metadata(url: DriveLinkChecks.refreshedViewer, publicAccess: true) }
                return try DriveLinkChecks.baseUploadResponder(request)
            }
            model.sharing = .anyoneWithLink
            model.uploadAndCopy(service)
            try await settle(model)
            assert(trace.uploadTransfers == 1 && trace.uploadStarts == 1)
            assert(DriveMockTrace.body(trace.requests.first(where: { $0.httpMethod == "PUT" })!) == expected, "Upload must use exactly the lossless exported PNG bytes")
            assert(model.pendingUploadCount == 0 && model.uploadResult?.warning != nil && copied.isEmpty)
            assert(model.history.first?.upload?.requestedSharing == .anyoneWithLink)
            model.sharing = .privateAccess // Changing new-upload defaults cannot alter retry policy.
            permissionFails = false
            model.retryLinkPublishing(service)
            try await settle(model)
            assert(trace.uploadTransfers == 1 && trace.uploadStarts == 1, "Sharing retry cannot upload image again")
            assert(model.uploadResult?.isPublic == true && copied.last == DriveLinkChecks.refreshedViewer)
            assert(trace.permissionRequests.count == 2)
            let saved = model.history.first!
            model.load(image, name: "Different screenshot")
            assert(model.uploadResult == nil, "Loading a different screenshot must clear the previous link")
            model.restore(saved)
            assert(model.uploadResult?.fileID == "file_fixture", "History must restore this screenshot's own uploaded link")
        }
        for asset in BackgroundLibrary.assets where !asset.photograph {
            assert(BackgroundLibrary.thumbnail(asset.id) != nil)
        }
        let background = BackgroundLibrary.image("ribbon")!
        assert(ImageEngine.pixelSize(background) == CGSize(width: 3840, height: 2400))
        print("PASS editor upload integration: exact PNG bytes, partial sharing recovery, no duplicate upload, policy snapshot, link history, original 4K backgrounds")
    }
    @MainActor static func settle(_ model: EditorModel) async throws {
        for _ in 0..<300 { if !model.busy { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw DriveLinkChecks.Failure("Fixture upload did not finish")
    }
}
