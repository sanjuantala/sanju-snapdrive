import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct SavedPreset: Codable, Identifiable { var id = UUID(); var name: String; var style: EditorStyle }
struct HistoryItem: Codable, Identifiable {
    var id: UUID; var name: String; var date: Date; var style: EditorStyle; var annotations: [Annotation]; var upload: DriveUploadResult? = nil
}
enum EditorTool: String, CaseIterable {
    case select, arrow, text, rectangle, ellipse, redact, pixelate, crop, blur, textselect, magnifier
    var icon: String { switch self { case .select: return "cursorarrow"; case .arrow: return "arrow.up.right"; case .text: return "textformat"; case .rectangle: return "rectangle"; case .ellipse: return "circle"; case .redact: return "rectangle.fill"; case .pixelate: return "square.grid.3x3.fill"; case .crop: return "crop"; case .blur: return "drop.halffull"; case .textselect: return "text.viewfinder"; case .magnifier: return "plus.magnifyingglass" } }
    var title: String { self == .textselect ? "Select text" : rawValue.capitalized }
    var annotationKind: AnnotationKind? { AnnotationKind(rawValue: rawValue) }
    var shortcutLetter: String {
        switch self {
        case .select:return "V";case .arrow:return "A";case .text:return "T";case .rectangle:return "R"
        case .ellipse:return "E";case .redact:return "X";case .pixelate:return "P";case .crop:return "C"
        case .blur:return "B";case .textselect:return "O";case .magnifier:return "M"
        }
    }
    static func fromShortcut(_ value: String) -> EditorTool? { allCases.first { $0.shortcutLetter.lowercased() == value.lowercased() } }
}
struct EditSnapshot {
    var image: NSImage?; var style: EditorStyle; var annotations: [Annotation]; var backgroundImage: NSImage?
    var selectedID: UUID? = nil
    var tool: EditorTool = .select
    var historyID: UUID? = nil
    var fileName = "Screenshot"
    var upload: DriveUploadResult? = nil
    var savedURL: URL? = nil
}
private struct DrawingDefaults: Codable {
    var colorHex = "#FF4A64"
    var lineWidth = 4.0
    var fontSize: Double?
    var magnification = 2.0
}

@MainActor final class EditorModel: ObservableObject {
    @Published var image: NSImage? { didSet { if oldValue !== image { sourceDirty = true; preview = nil }; imageRevision += 1; invalidateRecognition() } }
    @Published var preview: NSImage?
    @Published var style = EditorStyle() { didSet { refresh() } }
    @Published var annotations: [Annotation] = [] { didSet { imageRevision += 1; invalidateRecognition(); refresh() } }
    @Published var backgroundImage: NSImage? { didSet { if oldValue !== backgroundImage { backgroundDirty = true }; refresh() } }
    @Published var tool: EditorTool = .select {
        didSet {
            // An old object's appearance must never become the next drawing's default.
            if oldValue != tool && tool != .select { selectedID = nil; syncSelectedAppearance() }
        }
    }
    @Published var selectedID: UUID? { didSet { if selectedID != oldValue { syncSelectedAppearance() } } }
    @Published var ink = Color(red: 1, green: 0.29, blue: 0.39)
    @Published var lineWidth = 4.0
    @Published var fontSize = 28.0
    @Published var magnification = 2.0
    @Published var textInput = ""
    @Published var status = "Capture, open, or paste an image to begin."
    @Published var error: String?
    @Published var history: [HistoryItem] = []
    @Published var presets: [SavedPreset] = []
    @Published var undoStack: [EditSnapshot] = []
    @Published var redoStack: [EditSnapshot] = []
    @Published var recognized: [RecognizedLine] = []
    @Published var recognizing = false
    @Published var fileName = "Screenshot"
    @Published var exportFormat = "png"
    @Published var quality = 0.9
    @Published var driveMode = "folder" { didSet { preferences.set(driveMode, forKey: "driveMode") } }
    @Published var zoom = 0.0 {
        didSet {
            let safe = zoom.isFinite ? (zoom == 0 ? 0 : min(4,max(0.1,zoom))) : 0
            if zoom != safe { zoom = safe }
            if oldValue != zoom && !zoomInteracting { refresh() }
        }
    }
    @Published private(set) var zoomInteracting = false
    @Published var sharing: DriveSharing = .anyoneWithLink { didSet { preferences.set(sharing.rawValue, forKey: "sharing") } }
    @Published var autoBalanceCapture = true { didSet { preferences.set(autoBalanceCapture, forKey: "autoBalanceCapture") } }
    @Published var autoMatchBackground = false { didSet { preferences.set(autoMatchBackground, forKey: "autoMatchBackground") } }
    @Published var autoWindowStyle = false { didSet { preferences.set(autoWindowStyle, forKey: "autoWindowStyle") } }
    @Published var uploadResult: DriveUploadResult?
    @Published var showUploadResult = false
    @Published var pendingUploadCount = 0
    @Published var showDrive = false
    @Published var showHistory = false
    @Published var showText = false
    @Published var showShortcuts = false
    @Published var busy = false
    @Published var lastSavedURL: URL?
    @Published private(set) var toast: String?
    private var toastDismissal: Task<Void, Never>?
    private var sourceDirty = false
    private var backgroundDirty = false
    private var renderRevision = 0
    @Published private(set) var previewRendering = false
    private var renderedRevision = -1
    var previewIsCurrent: Bool { preview != nil && !previewRendering && renderedRevision == renderRevision }
    private let previewQueue = DispatchQueue(label: "SnapDrive.preview", qos: .userInitiated)
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private(set) var previewRenderCount = 0
    private(set) var sourceWriteCount = 0
    var currentHistoryID: UUID?
    var onNewImage: (() -> Void)?
    private var persistTask: DispatchWorkItem?
    private let imageImporter = ImageImportService()
    private var importTask: Task<Void, Never>?
    private var importID: UUID?
    private var imageRevision = 0
    private var recognitionID: UUID?
    private let textRecognizer: @Sendable (NSImage) throws -> [RecognizedLine]
    private let sensitiveRecognizer: @Sendable (NSImage) throws -> [Annotation]
    private struct AnnotationEdit { var id: UUID; var baseline: EditSnapshot }
    private var annotationEdit: AnnotationEdit?
    private var colorUndoGroup: (id: UUID, undoCount: Int, lastChange: TimeInterval)?
    private struct PendingUpload: Codable {
        var url: URL; var name: String; var historyID: UUID?; var sharing: DriveSharing; var copyLink: Bool; var uploaded: DriveUploadResult? = nil; var connection: String? = nil; var folderID: String? = nil
    }
    private var pendingUploads: [PendingUpload] = []
    private let storageDirectory: URL
    private let preferences: UserDefaults
    private var drawingDefaults = DrawingDefaults()
    private let clipboardWriter: (String) -> Bool
    private var root: URL {
        let url = storageDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    init(storageDirectory: URL? = nil, preferences: UserDefaults = .standard, clipboardWriter: ((String) -> Void)? = nil,
         recognizeText: (@Sendable (NSImage) throws -> [RecognizedLine])? = nil,
         detectSensitive: (@Sendable (NSImage) throws -> [Annotation])? = nil) {
        self.storageDirectory = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SnapDrive", isDirectory: true)
        self.preferences = preferences
        if let clipboardWriter { self.clipboardWriter = { text in clipboardWriter(text); return true } }
        else { self.clipboardWriter = { text in NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(text, forType: .string) } }
        self.textRecognizer = recognizeText ?? { try ImageEngine.recognize(image: $0) }
        self.sensitiveRecognizer = detectSensitive ?? { try ImageEngine.sensitiveAnnotations(image: $0) }
        if let data = preferences.data(forKey: "drawingDefaults"), let saved = try? JSONDecoder().decode(DrawingDefaults.self, from: data) {
            drawingDefaults = saved
            drawingDefaults.lineWidth = saved.lineWidth.isFinite ? min(1000,max(0.5,saved.lineWidth)) : 4
            drawingDefaults.fontSize = saved.fontSize.flatMap { $0.isFinite ? min(512,max(8,$0)) : nil }
            drawingDefaults.magnification = saved.magnification.isFinite ? min(8,max(1,saved.magnification)) : 2
        }
        syncSelectedAppearance()
        thumbnailCache.totalCostLimit = 12 * 1024 * 1024
        driveMode = preferences.string(forKey: "driveMode") ?? "folder"
        sharing = DriveSharing(rawValue: preferences.string(forKey: "sharing") ?? "anyoneWithLink") ?? .anyoneWithLink
        autoBalanceCapture = preferences.object(forKey: "autoBalanceCapture") as? Bool ?? true
        autoMatchBackground = preferences.bool(forKey: "autoMatchBackground")
        autoWindowStyle = preferences.bool(forKey: "autoWindowStyle")
        if let data = try? Data(contentsOf: root.appendingPathComponent("pending-uploads.json")), let list = try? JSONDecoder().decode([PendingUpload].self, from: data) { pendingUploads = list.filter { FileManager.default.fileExists(atPath: $0.url.path) }; pendingUploadCount = pendingUploads.count }
        if let data = try? Data(contentsOf: root.appendingPathComponent("history.json")), let list = try? JSONDecoder().decode([HistoryItem].self, from: data) { history = list }
        if let data = preferences.data(forKey: "presets"), let list = try? JSONDecoder().decode([SavedPreset].self, from: data) { presets = list }
        if let data = preferences.data(forKey: "defaultStyle"), let saved = try? JSONDecoder().decode(EditorStyle.self, from: data) { style = saved }
    }
    var activeBackgroundImage: NSImage? {
        if style.background.hasPrefix("image:") { return BackgroundLibrary.image(String(style.background.dropFirst(6))) }
        return backgroundImage
    }
    func refresh() {
        renderRevision += 1
        renderPreview()
        persistTask?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.persistCurrent() }
        persistTask = item; DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: item)
    }
    private func renderPreview() {
        guard !previewRendering else { return }
        guard let image else { preview = nil; return }
        let revision = renderRevision, style = self.style, annotations = self.annotations
        let cap: CGFloat? = zoom == 0 || zoomInteracting || annotationEdit != nil ? 1800 : nil
        let background: NSImage?
        if style.background.hasPrefix("image:"), let cap {
            background = BackgroundLibrary.previewImage(String(style.background.dropFirst(6)), maxPixelDimension: Int(cap))
        } else { background = activeBackgroundImage }
        let size = ImageEngine.dimensions(image: image, style: style)
        if size.width * size.height <= 1_000_000 {
            previewRenderCount += 1
            preview = autoreleasepool { ImageEngine.render(image: image, style: style, annotations: annotations, backgroundImage: background, maxPixelDimension: cap) }
            renderedRevision = revision
            return
        }
        previewRendering = true
        previewQueue.async { [weak self] in
            let result = autoreleasepool { ImageEngine.render(image: image, style: style, annotations: annotations, backgroundImage: background, maxPixelDimension: cap) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.previewRendering = false; self.previewRenderCount += 1
                if revision == self.renderRevision { self.preview = result; self.renderedRevision = revision }
                else { self.renderPreview() }
            }
        }
    }
    func commitActiveText() { NotificationCenter.default.post(name: .snapDriveCommitText, object: self) }
    func beginZoomInteraction() {
        guard !zoomInteracting else { return }
        zoomInteracting = true; refresh()
    }
    func endZoomInteraction() {
        guard zoomInteracting else { return }
        zoomInteracting = false; refresh()
    }
    func requestZoom(_ command: String) {
        guard image != nil else { return }
        let old = zoom
        NotificationCenter.default.post(name: .snapDriveZoomRequest, object: self, userInfo: ["command":command])
        if zoom == old {
            switch command {
            case "in": zoom = min(4,(zoom == 0 ? 1 : zoom)*1.2)
            case "out": zoom = max(0.1,(zoom == 0 ? 1 : zoom)/1.2)
            case "fit": zoom = 0
            case "actual": zoom = 1
            default: break
            }
        }
    }
    func requestZoom(value: Double) {
        guard image != nil else { return }
        let old = zoom
        NotificationCenter.default.post(name: .snapDriveZoomRequest, object: self, userInfo: ["value":value])
        if zoom == old { zoom = value }
    }
    func showToast(_ message: String) {
        toastDismissal?.cancel(); toast = message
        toastDismissal = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 2_800_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
    func checkpoint() {
        finishAnnotationEdit()
        colorUndoGroup = nil
        guard image != nil else { return }
        recordUndo(snapshot())
    }
    func undo() {
        commitActiveText()
        finishAnnotationEdit(); colorUndoGroup = nil
        guard let old = undoStack.popLast() else { return }
        let current = snapshot()
        persistCurrent()
        redoStack.append(current); restoreSnapshot(old)
        status = "Edit undone."
    }
    func redo() {
        commitActiveText()
        finishAnnotationEdit(); colorUndoGroup = nil
        guard let next = redoStack.popLast() else { return }
        let current = snapshot()
        persistCurrent()
        undoStack.append(current); restoreSnapshot(next)
        status = "Edit redone."
    }
    private func snapshot() -> EditSnapshot {
        EditSnapshot(image: image, style: style, annotations: annotations, backgroundImage: backgroundImage, selectedID: selectedID, tool: tool, historyID: currentHistoryID, fileName: fileName, upload: uploadResult, savedURL: lastSavedURL)
    }
    private func recordUndo(_ snapshot: EditSnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > 35 { undoStack.removeFirst() }
        // Annotation-only snapshots share their source. Destructive image edits do
        // not get to retain 35 separate Retina bitmaps indefinitely.
        while undoStack.count > 1 && undoBitmapBytes() > 128 * 1024 * 1024 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    private func undoBitmapBytes() -> Double {
        var seen = Set<ObjectIdentifier>(), bytes = 0.0
        for snapshot in undoStack {
            for image in [snapshot.image, snapshot.backgroundImage].compactMap({ $0 }) where seen.insert(ObjectIdentifier(image)).inserted {
                let size = ImageEngine.pixelSize(image); bytes += size.width * size.height * 4
            }
        }
        return bytes
    }
    private func restoreSnapshot(_ snapshot: EditSnapshot) {
        let changesDocument = (image == nil) != (snapshot.image == nil) || currentHistoryID != snapshot.historyID
        if changesDocument {
            currentHistoryID = snapshot.historyID; fileName = snapshot.fileName
            let latestUpload = snapshot.historyID.flatMap { id in history.first { $0.id == id }?.upload }
            uploadResult = latestUpload ?? snapshot.upload
            lastSavedURL = uploadResult?.shareURL ?? snapshot.savedURL; showUploadResult = false
        }
        image = snapshot.image; style = snapshot.style; annotations = snapshot.annotations; backgroundImage = snapshot.backgroundImage
        tool = snapshot.tool
        selectedID = snapshot.selectedID.flatMap { id in annotations.contains(where: { $0.id == id }) ? id : nil }
        syncSelectedAppearance(); refresh()
    }
    func selectAnnotation(_ id: UUID?) {
        if annotationEdit?.id != id { finishAnnotationEdit() }
        if selectedID != id { colorUndoGroup = nil }
        selectedID = id.flatMap { target in annotations.contains(where: { $0.id == target }) ? target : nil }
        syncSelectedAppearance()
    }
    /// A drag owns one baseline. Mouse updates never create individual undo entries.
    @discardableResult func beginAnnotationEdit(id: UUID) -> Bool {
        guard annotations.contains(where: { $0.id == id }) else { return false }
        if annotationEdit?.id == id { return true }
        finishAnnotationEdit(); colorUndoGroup = nil; selectAnnotation(id)
        let baseline = snapshot()
        annotationEdit = AnnotationEdit(id: id, baseline: baseline)
        return true
    }
    func updateAnnotationEdit(_ annotation: Annotation) {
        guard annotationEdit?.id == annotation.id,
              let safe = validated(annotation), let index = annotations.firstIndex(where: { $0.id == annotation.id }), annotations[index] != safe else { return }
        annotations[index] = safe
    }
    func finishAnnotationEdit(cancelled: Bool = false) {
        guard let edit = annotationEdit else { return }
        annotationEdit = nil
        if cancelled { restoreSnapshot(edit.baseline) }
        else if edit.baseline.annotations != annotations { recordUndo(edit.baseline); syncSelectedAppearance() }
        refresh()
    }
    func nudgeSelected(delta: CGPoint) {
        guard delta.x.isFinite, delta.y.isFinite, let image, let id = selectedID,
              let original = annotations.first(where: { $0.id == id }) else { return }
        let moved = EditorInteraction.moved(original, delta: delta, pixels: ImageEngine.pixelSize(image))
        guard moved != original, beginAnnotationEdit(id: id) else { return }
        updateAnnotationEdit(moved); finishAnnotationEdit()
    }
    /// Native text editing stays local until this commit; Escape never mutates the model.
    @discardableResult func commitText(_ text: String, at point: CGPoint, replacing id: UUID? = nil) -> UUID? {
        guard image != nil, point.x.isFinite, point.y.isFinite else { return nil }
        finishAnnotationEdit(); colorUndoGroup = nil
        let text = String(text.prefix(2000))
        if let id {
            guard let index = annotations.firstIndex(where: { $0.id == id && $0.kind == .text }) else { return nil }
            selectAnnotation(id)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { removeSelected(); return nil }
            guard annotations[index].text != text else { return id }
            checkpoint(); annotations[index].text = text; textInput = text; syncSelectedAppearance(); status = "Text updated."
            return id
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let start = CGPoint(x: min(1,max(0,point.x)),y: min(1,max(0,point.y)))
        let annotation = Annotation(kind: .text, start: start, end: start, text: text, colorHex: ink.hexString, lineWidth: lineWidth, fontSize: fontSize)
        add(annotation); textInput = text; status = "Text added. Double-click to edit."
        return annotation.id
    }
    private func validated(_ annotation: Annotation) -> Annotation? {
        guard [annotation.start.x, annotation.start.y, annotation.end.x, annotation.end.y].allSatisfy({ $0.isFinite }) else { return nil }
        var safe = annotation
        safe.start = CGPoint(x: min(1,max(0,safe.start.x)),y: min(1,max(0,safe.start.y)))
        safe.end = CGPoint(x: min(1,max(0,safe.end.x)),y: min(1,max(0,safe.end.y)))
        safe.fontSize = safe.fontSize.isFinite ? min(512,max(8,safe.fontSize)) : 28
        safe.lineWidth = safe.lineWidth.isFinite ? min(1000,max(0.5,safe.lineWidth)) : 4
        safe.magnification = safe.magnification.isFinite ? min(8,max(1,safe.magnification)) : 2
        if safe.kind == .magnifier, let image {
            let rect = ImageEngine.magnifierBounds(safe, pixels: ImageEngine.pixelSize(image))
            safe.start = rect.origin; safe.end = CGPoint(x: rect.maxX, y: rect.maxY)
        }
        safe.text = String(safe.text.prefix(2000))
        return safe
    }
    func captureAppearance(_ original: NSImage, window: Bool = false) -> (image: NSImage, style: EditorStyle) {
        let image = autoBalanceCapture ? (ImageEngine.autoBalanced(image: original) ?? original) : original
        var style = self.style
        if window && autoWindowStyle { style.inset = 0; style.radius = 12 }
        if autoMatchBackground, let hex = Self.averageColor(image) { style.solidHex = hex; style.background = "solid" }
        return (image, style)
    }
    func load(_ original: NSImage, name: String = "Screenshot", captured: Bool = false, window: Bool = false) {
        importTask?.cancel(); importTask = nil; importID = nil
        commitActiveText()
        finishAnnotationEdit(); colorUndoGroup = nil
        persistCurrent()
        zoom = 0; zoomInteracting = false
        let stableOriginal = ImageEngine.materializedImage(original) ?? original
        let prepared = captured ? captureAppearance(stableOriginal, window: window) : (image: stableOriginal, style: style)
        let image = prepared.image; style = prepared.style
        self.image = image; uploadResult = nil; showUploadResult = false; lastSavedURL = nil; annotations = []; selectedID = nil; recognized = []; undoStack = []; redoStack = []; fileName = name; zoom = 0; tool = .arrow; textInput = ""
        let id = UUID(); currentHistoryID = id; sourceDirty = true; backgroundDirty = true
        syncSelectedAppearance()
        history.insert(HistoryItem(id: id, name: name, date: Date(), style: style, annotations: []), at: 0)
        while history.count > 100 { let removed = history.removeLast(); try? FileManager.default.removeItem(at: root.appendingPathComponent("\(removed.id).png")); try? FileManager.default.removeItem(at: root.appendingPathComponent("\(removed.id)-background.png")) }
        NSApp?.keyWindow?.makeFirstResponder(nil)
        refresh(); persistCurrent(); status = "Ready to edit · All processing stays on your Mac"; onNewImage?()
    }
    func open(_ url: URL? = nil) {
        guard let target = url else {
            imageImporter.choose { [weak self] in self?.open($0) }
            return
        }
        importTask?.cancel()
        let request = UUID(); importID = request
        status = "Opening \(target.lastPathComponent)…"
        importTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Result { try ImageImportService.readData(target) } }.value
            guard let self, !Task.isCancelled, self.importID == request else { return }
            self.importTask = nil; self.importID = nil
            switch result {
            case .success(let data):
                do { self.load(try ImageImportService.decodeData(data), name: target.deletingPathExtension().lastPathComponent) }
                catch { self.status = "Image could not be opened"; self.error = "Could not open \(target.lastPathComponent). \(error.localizedDescription)" }
            case .failure(let failure):
                self.status = "Image could not be opened"
                self.error = "Could not open \(target.lastPathComponent). \(failure.localizedDescription)"
            }
        }
    }
    func paste() {
        if let image = (NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first { load(image, name: "Clipboard") }
        else { status = "The clipboard does not contain an image." }
    }
    func restore(_ item: HistoryItem) {
        importTask?.cancel(); importTask = nil; importID = nil
        commitActiveText()
        finishAnnotationEdit(); colorUndoGroup = nil
        persistCurrent()
        zoom = 0; zoomInteracting = false
        guard let image = NSImage(contentsOf: root.appendingPathComponent("\(item.id).png")) else { error = "This history image is no longer available."; return }
        currentHistoryID = item.id; backgroundImage = NSImage(contentsOf: root.appendingPathComponent("\(item.id)-background.png")); self.image = image; fileName = item.name; style = item.style; annotations = item.annotations; undoStack = []; redoStack = []; recognized = []; selectedID = nil; showHistory = false; uploadResult = item.upload; lastSavedURL = item.upload?.shareURL; showUploadResult = false; zoom = 0; tool = .select; textInput = ""; sourceDirty = false; backgroundDirty = false; refresh()
    }
    func thumbnail(_ item: HistoryItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let image = thumbnailCache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithURL(root.appendingPathComponent("\(item.id).png") as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 340, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnailCache.setObject(image, forKey: key, cost: cg.width * cg.height * 4)
        return image
    }
    func clearHistory() {
        for item in history { try? FileManager.default.removeItem(at: root.appendingPathComponent("\(item.id).png")); try? FileManager.default.removeItem(at: root.appendingPathComponent("\(item.id)-background.png")) }
        history = []; currentHistoryID = nil; thumbnailCache.removeAllObjects(); persistCurrent()
    }
    func persistCurrent() {
        if let id = currentHistoryID, let index = history.firstIndex(where: { $0.id == id }) {
            history[index].style = style; history[index].annotations = annotations
            if backgroundDirty, style.background == "custom", let backgroundImage, let data = ImageEngine.data(image: backgroundImage, format: "png", quality: 1) {
                do { try data.write(to: root.appendingPathComponent("\(id)-background.png"), options: .atomic); backgroundDirty = false } catch { self.error = "Could not save the background: \(error.localizedDescription)" }
            }
            if sourceDirty, let image, let data = ImageEngine.data(image: image, format: "png", quality: 1) {
                do { try data.write(to: root.appendingPathComponent("\(id).png"), options: .atomic); sourceDirty = false; sourceWriteCount += 1; thumbnailCache.removeObject(forKey: id.uuidString as NSString) } catch { self.error = "Could not save local history: \(error.localizedDescription)" }
            }
        }
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: root.appendingPathComponent("history.json"), options: .atomic) }
        if let data = try? JSONEncoder().encode(style) { preferences.set(data, forKey: "defaultStyle") }
    }
    func add(_ annotation: Annotation) {
        guard image != nil, let safe = validated(annotation), !annotations.contains(where: { $0.id == safe.id }) else { return }
        checkpoint(); annotations.append(safe); selectAnnotation(safe.id)
    }
    func removeSelected() {
        finishAnnotationEdit()
        guard let selectedID, annotations.contains(where: { $0.id == selectedID }) else { self.selectedID = nil; return }
        checkpoint(); annotations.removeAll { $0.id == selectedID }; self.selectedID = nil
        status = "Annotation deleted. Undo to restore."
    }
    func clearAnnotations() {
        commitActiveText()
        finishAnnotationEdit(); colorUndoGroup = nil
        guard !annotations.isEmpty else { showToast("No annotations to clear"); return }
        checkpoint(); annotations = []; selectedID = nil; tool = .select; textInput = ""
        status = "Annotations cleared. Undo to restore."
        showToast("Annotations cleared · Undo to restore")
    }
    /// Clears the current workspace, keeping its saved history and an undo snapshot.
    func clearCanvas() {
        importTask?.cancel(); importTask = nil; importID = nil
        commitActiveText(); finishAnnotationEdit(); colorUndoGroup = nil
        guard image != nil else { showToast("Canvas is already clear"); return }
        persistCurrent(); checkpoint()
        currentHistoryID = nil
        image = nil; zoomInteracting = false; annotations = []; selectedID = nil; recognized = []
        uploadResult = nil; showUploadResult = false; lastSavedURL = nil
        fileName = "Screenshot"; textInput = ""; zoom = 0; tool = .arrow
        refresh()
        status = "Canvas cleared. Undo to restore your screenshot."
        showToast("Canvas cleared · Undo to restore")
    }
    func crop(_ rect: CGRect) {
        commitActiveText()
        guard let image else { return }
        guard let flattened = ImageEngine.render(image: image, style: { var s = EditorStyle(); s.padding = 0; s.radius = 0; s.shadow = 0; s.background = "transparent"; return s }(), annotations: annotations), let result = ImageEngine.crop(image: flattened, rect: rect) else { return }
        checkpoint(); self.image = result; annotations = []; recognized = []; selectedID = nil; tool = .select; refresh(); status = "Image cropped. Undo to restore."
    }
    func balance() {
        commitActiveText()
        guard let image else { return }
        var flat = EditorStyle(); flat.padding = 0; flat.radius = 0; flat.shadow = 0; flat.background = "transparent"
        let source: NSImage
        if annotations.isEmpty { source = image }
        else { guard let rendered = ImageEngine.render(image: image, style: flat, annotations: annotations) else { error = "Could not safely flatten annotations for balancing. Reduce the image size first."; return }; source = rendered }
        if let result = ImageEngine.autoBalanced(image: source) {
            guard result !== image || !annotations.isEmpty else { status = "Content is already balanced."; return }
            checkpoint(); self.image = result; annotations = []; recognized = []; selectedID = nil; refresh(); status = "Content balanced. Annotations were preserved in the image. Undo to restore layers."
        }
    }
    private func flattenedSource() -> NSImage? {
        guard let image else { return nil }; if annotations.isEmpty { return image }
        var flat = EditorStyle(); flat.padding = 0; flat.inset = 0; flat.radius = 0; flat.shadow = 0; flat.background = "transparent"
        guard let rendered = ImageEngine.render(image: image, style: flat, annotations: annotations) else { error = "Could not prepare the edited image for text recognition."; return nil }; return rendered
    }
    func recognize(copy: Bool = false, redact: Bool = false, region: CGRect? = nil) {
        guard !recognizing, let rawImage = flattenedSource() else { return }
        let image: NSImage
        if let region { guard let cropped = ImageEngine.crop(image: rawImage, rect: region) else { error = "Choose a valid region for text recognition."; return }; image = cropped }
        else { image = rawImage }
        let sourceID = currentHistoryID; let revision = imageRevision; let jobID = UUID()
        recognitionID = jobID; recognizing = true
        let detectSensitive = sensitiveRecognizer; let recognizeText = textRecognizer
        let selectedRegion = region?.standardized.intersection(CGRect(x: 0,y: 0,width: 1,height: 1))
        Task { @MainActor in
            defer { if recognitionID == jobID { recognizing = false; recognitionID = nil } }
            do {
                if redact {
                    var found = try await Task.detached(priority: .userInitiated) { try detectSensitive(image) }.value
                    guard recognitionID == jobID && sourceID == currentHistoryID && revision == imageRevision else { return }
                    if let region = selectedRegion {
                        found = found.map { item in var a = item; a.start = CGPoint(x: region.minX+a.start.x*region.width,y: region.minY+a.start.y*region.height); a.end = CGPoint(x: region.minX+a.end.x*region.width,y: region.minY+a.end.y*region.height); return a }
                    }
                    if !found.isEmpty { checkpoint(); annotations += found }
                    status = "Added \(found.count) suggested redactions. Review the image before sharing."
                } else {
                    var lines = try await Task.detached(priority: .userInitiated) { try recognizeText(image) }.value
                    guard recognitionID == jobID && sourceID == currentHistoryID && revision == imageRevision else { return }
                    if let region = selectedRegion { lines = lines.map { RecognizedLine(text: $0.text,rect: CGRect(x: region.minX+$0.rect.minX*region.width,y: region.minY+$0.rect.minY*region.height,width: $0.rect.width*region.width,height: $0.rect.height*region.height)) } }
                    recognized = lines
                    if copy { copyText(lines.map(\.text).joined(separator: "\n")) } else { showText = true }
                }
            } catch {
                guard recognitionID == jobID && sourceID == currentHistoryID && revision == imageRevision else { return }
                self.error = "Text recognition is unavailable: \(error.localizedDescription)"
            }
        }
    }
    private func invalidateRecognition() {
        recognitionID = nil; recognizing = false; recognized = []; showText = false
    }
    func copyText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "No text recognized."; return }
        guard clipboardWriter(text) else { error = "The text could not be copied. Try again."; return }
        status = "Recognized text copied."; showToast("Text copied")
    }
    func renderedOutput() -> NSImage? {
        commitActiveText()
        guard let image else { return nil }
        return ImageEngine.render(image: image, style: style, annotations: annotations, backgroundImage: activeBackgroundImage)
    }
    func output() -> (Data, String)? {
        guard let rendered = renderedOutput(), let data = ImageEngine.data(image: rendered, format: exportFormat, quality: quality) else { error = "Could not render the screenshot."; return nil }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return (data, "\(fileName.replacingOccurrences(of: "/", with: "-")) \(df.string(from: Date())).\(exportFormat == "png" ? "png" : "jpg")")
    }
    func save() {
        guard let (data, name) = output() else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = exportFormat == "png" ? [.png] : [.jpeg]; panel.nameFieldStringValue = name
        panel.begin { response in guard response == .OK, let url = panel.url else { return }; do { try data.write(to: url, options: .atomic); self.lastSavedURL = url; self.status = "Saved \(url.lastPathComponent)"; self.persistCurrent() } catch { self.error = error.localizedDescription } }
    }
    func saveDrive(_ drive: DriveService, automatic: Bool = false) {
        if driveMode == "folder" { saveToDriveFolder(drive, automatic: automatic) }
        else { enqueueUpload(drive, copyLink: !automatic) }
    }
    func saveToDriveFolder(_ drive: DriveService, automatic: Bool = false) {
        guard image != nil else { return }
        if drive.syncFolder.isEmpty {
            if automatic { status = "Choose a Drive folder to enable automatic saving."; return }
            drive.chooseSyncFolder { self.saveToDriveFolder(drive) }; return
        }
        guard let (data, name) = output() else { return }
        do { lastSavedURL = try drive.saveToSyncFolder(data: data, name: name); status = "Saved to your Drive folder. Drive for desktop manages syncing."; persistCurrent() }
        catch { self.error = error.localizedDescription }
    }
    func uploadAndCopy(_ drive: DriveService) {
        guard image != nil, !busy else { return }
        guard drive.isConnected else { driveMode = "api"; showDrive = true; status = "Connect Google Drive to upload and get a link."; return }
        enqueueUpload(drive, copyLink: true)
    }
    private func enqueueUpload(_ drive: DriveService, copyLink: Bool) {
        guard drive.isConnected else { status = "Connect Google Drive before uploading."; if copyLink { driveMode = "api"; showDrive = true }; return }
        guard let (data, name) = output() else { return }
        do {
            let folder = root.appendingPathComponent("Pending uploads", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(UUID().uuidString + "-" + name)
            try data.write(to: url, options: .atomic)
            pendingUploads.append(PendingUpload(url: url, name: name, historyID: currentHistoryID, sharing: sharing, copyLink: copyLink, connection: drive.connectionFingerprint, folderID: drive.folderID))
            persistQueue(); status = "Screenshot queued for Google Drive upload."; processNextUpload(drive)
        } catch { self.error = error.localizedDescription }
    }
    private func persistQueue() {
        pendingUploadCount = pendingUploads.count
        if let data = try? JSONEncoder().encode(pendingUploads) { try? data.write(to: root.appendingPathComponent("pending-uploads.json"), options: .atomic) }
    }
    func retryPendingUploads(_ drive: DriveService) {
        guard drive.isConnected else { status = "Connect Google Drive to retry pending uploads."; return }
        // The Retry UI explicitly confirms the current account/folder as the destination.
        for index in pendingUploads.indices { pendingUploads[index].connection = drive.connectionFingerprint; pendingUploads[index].folderID = drive.folderID }
        persistQueue(); processNextUpload(drive)
    }
    func showPendingUploads() { NSWorkspace.shared.open(root.appendingPathComponent("Pending uploads", isDirectory: true)) }
    private func processNextUpload(_ drive: DriveService) {
        guard !busy, let item = pendingUploads.first else { return }
        guard item.connection == drive.connectionFingerprint, item.folderID == drive.folderID else { status = "Pending uploads paused: the Google connection or destination changed. Review Drive settings, then Retry."; return }
        busy = true
        Task { @MainActor in
            do {
                let uploaded: DriveUploadResult
                if let existing = item.uploaded { uploaded = existing }
                else {
                    let data = try Data(contentsOf: item.url)
                    uploaded = try await drive.uploadFile(data: data, name: item.name)
                    pendingUploads[0].uploaded = uploaded
                    // The default app folder may have just been resolved. Keep queued jobs on that destination.
                    if item.folderID == "" {
                        for index in pendingUploads.indices where pendingUploads[index].folderID == "" && pendingUploads[index].connection == item.connection { pendingUploads[index].folderID = drive.folderID }
                    }
                    persistQueue()
                }
                let result = await drive.publishLink(for: uploaded, sharing: item.sharing)
                // Uploaded metadata is persisted before publishing; permission retries never reupload.
                pendingUploads.removeFirst(); persistQueue(); try? FileManager.default.removeItem(at: item.url)
                if item.historyID == currentHistoryID { lastSavedURL = result.shareURL; uploadResult = result }
                if let id = item.historyID, let index = history.firstIndex(where: { $0.id == id }) { history[index].upload = result }
                persistCurrent()
                if let warning = result.warning { status = "Uploaded. \(warning)" }
                else { status = result.isPublic ? "Uploaded · Anyone with the link can view" : "Uploaded · Existing Drive access applies" }
                if item.copyLink && item.historyID == currentHistoryID { if result.warning == nil { copyUploadLink(result) } else { showUploadResult = true } }
                busy = false; processNextUpload(drive)
            } catch {
                busy = false; status = "Upload paused · \(pendingUploads.count) pending"
                self.error = "Upload failed: \(error.localizedDescription) The screenshot is saved locally. Use Retry pending uploads in Drive settings."
            }
        }
    }
    func retryLinkPublishing(_ drive: DriveService) {
        guard let result = uploadResult, !busy else { return }; busy = true
        Task { @MainActor in
            let updated = await drive.publishLink(for: result, sharing: result.requestedSharing)
            uploadResult = updated; lastSavedURL = updated.shareURL
            for index in history.indices where history[index].upload?.fileID == updated.fileID { history[index].upload = updated }
            persistCurrent(); busy = false
            if updated.warning == nil { copyUploadLink(updated) }
        }
    }
    func copyUploadLink(_ result: DriveUploadResult? = nil) {
        guard let result = result ?? uploadResult, result.hasVerifiedDriveURL else { return }
        guard clipboardWriter(result.shareURL.absoluteString) else { error = "The Drive link could not be copied. Try again."; return }
        status = result.isPublic ? "Drive link copied · Anyone with the link can view" : "Drive link copied · Existing Drive access applies"
        showToast("Drive link copied")
    }
    func copyImage() {
        guard let rendered = renderedOutput(), let png = ImageEngine.data(image: rendered, format: "png", quality: 1) else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setData(png, forType: .png) { status = "Edited image copied."; showToast("Screenshot copied") }
        else { error = "The screenshot could not be copied. Try again." }
    }
    func applySelectedAppearance() {
        guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        var updated = annotations[index]
        updated.colorHex = ink.hexString; updated.lineWidth = lineWidth; updated.fontSize = fontSize
        if updated.kind == .text { updated.text = textInput }
        guard let safe = validated(updated), safe != annotations[index] else { return }
        checkpoint(); annotations[index] = safe
    }
    /// Only explicit user changes persist drawing defaults; selecting or undoing does not.
    func setSelectedColor(_ color: Color) {
        finishAnnotationEdit()
        ink = color; drawingDefaults.colorHex = color.hexString; storeDrawingDefaults()
        guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].colorHex != color.hexString else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let continues = colorUndoGroup.map { $0.id == id && $0.undoCount == undoStack.count && now-$0.lastChange < 0.6 } ?? false
        if !continues { checkpoint() }
        annotations[index].colorHex = color.hexString
        colorUndoGroup = (id,undoStack.count,now)
    }
    func setSelectedLineWidth(_ width: Double) {
        finishAnnotationEdit(); colorUndoGroup = nil
        lineWidth = width.isFinite ? min(1000,max(0.5,width)) : 4
        drawingDefaults.lineWidth = lineWidth; storeDrawingDefaults()
        guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].lineWidth != lineWidth else { return }
        checkpoint(); annotations[index].lineWidth = lineWidth
    }
    func setSelectedFontSize(_ size: Double) {
        finishAnnotationEdit(); colorUndoGroup = nil
        fontSize = size.isFinite ? min(512,max(8,size)) : 28
        drawingDefaults.fontSize = fontSize; storeDrawingDefaults()
        guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].fontSize != fontSize else { return }
        checkpoint(); annotations[index].fontSize = fontSize
    }
    func syncSelectedAppearance() {
        guard let id = selectedID, let a = annotations.first(where: { $0.id == id }) else {
            ink = Color(nsColor: NSColor(hex: drawingDefaults.colorHex)); lineWidth = drawingDefaults.lineWidth
            fontSize = drawingDefaults.fontSize ?? image.map { min(144,max(28,(ImageEngine.pixelSize($0).width * 0.025).rounded())) } ?? 28
            magnification = drawingDefaults.magnification
            return
        }
        ink = Color(nsColor: NSColor(hex: a.colorHex)); lineWidth = a.lineWidth; fontSize = a.fontSize
        if a.kind == .magnifier { magnification = a.magnification }
        if a.kind == .text { textInput = a.text }
    }
    var selectedMagnifier: Annotation? { annotations.first { $0.id == selectedID && $0.kind == .magnifier } }
    var magnifierDiameter: Double {
        guard let image else { return 160 }
        let pixels = ImageEngine.pixelSize(image)
        if let annotation = selectedMagnifier { return ImageEngine.magnifierBounds(annotation, pixels: pixels).width * pixels.width }
        return min(min(pixels.width,pixels.height),max(48,min(360,min(pixels.width,pixels.height)*0.28)))
    }
    func setSelectedMagnification(_ value: Double) {
        finishAnnotationEdit(); colorUndoGroup = nil
        magnification = value.isFinite ? min(8,max(1,value)) : 2
        drawingDefaults.magnification = magnification; storeDrawingDefaults()
        guard let id = selectedID, let index = annotations.firstIndex(where: { $0.id == id && $0.kind == .magnifier }), annotations[index].magnification != magnification else { return }
        checkpoint(); annotations[index].magnification = magnification
    }
    private func storeDrawingDefaults() {
        if let data = try? JSONEncoder().encode(drawingDefaults) { preferences.set(data, forKey: "drawingDefaults") }
    }
    func setSelectedMagnifierDiameter(_ value: Double) {
        guard value.isFinite, let image, let original = selectedMagnifier else { return }
        let pixels = ImageEngine.pixelSize(image), rect = ImageEngine.magnifierBounds(original, pixels: pixels)
        let target = EditorInteraction.circle(center: CGPoint(x:rect.midX,y:rect.midY), diameter: max(8,value), pixels: pixels)
        var resized = original; resized.start = target.origin; resized.end = CGPoint(x:target.maxX,y:target.maxY)
        guard resized != original, beginAnnotationEdit(id:original.id) else { return }
        updateAnnotationEdit(resized); finishAnnotationEdit()
    }
    func dragProvider() -> NSItemProvider {
        guard let (data, name) = output() else { return NSItemProvider() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SnapDrive-" + UUID().uuidString + "-" + name)
        do { try data.write(to: url); return NSItemProvider(contentsOf: url) ?? NSItemProvider() } catch { self.error = error.localizedDescription; return NSItemProvider() }
    }
    func savePreset(_ name: String) {
        let preset = SavedPreset(name: name.isEmpty ? "My style" : name, style: style)
        if style.background == "custom", let backgroundImage, let data = ImageEngine.data(image: backgroundImage, format: "png", quality: 1) { try? data.write(to: root.appendingPathComponent("preset-\(preset.id).png"), options: .atomic) }
        presets.append(preset); storePresets(); status = "Preset saved."
    }
    func applyPreset(_ preset: SavedPreset) { checkpoint(); backgroundImage = NSImage(contentsOf: root.appendingPathComponent("preset-\(preset.id).png")); style = preset.style }
    func deletePreset(_ id: UUID) { try? FileManager.default.removeItem(at: root.appendingPathComponent("preset-\(id).png")); presets.removeAll { $0.id == id }; storePresets() }
    func storePresets() { if let data = try? JSONEncoder().encode(presets) { preferences.set(data, forKey: "presets") } }
    func chooseBackground() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        panel.begin { response in
            guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
            self.checkpoint(); self.backgroundImage = image; self.style.background = "custom"
            if let data = ImageEngine.data(image: image, format: "png", quality: 1) { try? data.write(to: self.root.appendingPathComponent("background.png")) }
        }
    }
    func restoreBackground() { backgroundImage = NSImage(contentsOf: root.appendingPathComponent("background.png")) }
    func useWallpaper() { if let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen), let image = NSImage(contentsOf: url) { checkpoint(); backgroundImage = image; style.background = "custom" } else { error = "The current wallpaper cannot be read. Choose an image instead." } }
    func autoColor(recordUndo: Bool = true) {
        guard let image, let hex = Self.averageColor(image) else { return }
        if recordUndo { checkpoint() }; style.solidHex = hex; style.background = "solid"
    }
    private static func averageColor(_ image: NSImage) -> String? {
        guard let cg = ImageEngine.cgImage(image), let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high; ctx.draw(cg, in: CGRect(x: 0,y: 0,width: 1,height: 1)); guard let bytes = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }

}

extension Color {
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .systemPurple
        func channel(_ value: CGFloat) -> Int { value.isFinite ? Int((min(1,max(0,value))*255).rounded()) : 0 }
        return String(format: "#%02X%02X%02X",channel(c.redComponent),channel(c.greenComponent),channel(c.blueComponent))
    }
}
