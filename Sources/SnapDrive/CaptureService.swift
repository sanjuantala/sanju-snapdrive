import AppKit
import Carbon
import Combine
import CoreGraphics

/// The interactive macOS picker also switches between region and window selection with Space.
enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case region, window, fullscreen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .region: return "Capture Region"
        case .window: return "Capture Window"
        case .fullscreen: return "Capture Full Screen"
        }
    }
    var symbol: String {
        switch self {
        case .region: return "viewfinder"
        case .window: return "macwindow"
        case .fullscreen: return "display"
        }
    }
}

struct CaptureShortcut: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags (cmdKey, shiftKey, optionKey, controlKey).
    var modifiers: UInt32
    var display: String {
        let symbols: [(Int, String)] = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        let prefix = symbols.filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined()
        let keys: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",50:"`",65:".",67:"×",69:"+",75:"/",76:"↩",78:"−",81:"=",82:"0",83:"1",84:"2",85:"3",86:"4",87:"5",88:"6",89:"7",91:"8",92:"9",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",111:"F12",118:"F4",120:"F2",122:"F1"]
        return prefix + (keys[keyCode] ?? "Key \(keyCode)")
    }
}

@MainActor
final class CaptureService: NSObject, ObservableObject {
    @Published var busy = false
    @Published var status = "Ready to capture"
    @Published private(set) var needsScreenPermission = false
    static let supportedDelays = [0, 3, 5, 10]
    @Published var delaySeconds = 0 {
        didSet {
            let normalized = Self.supportedDelays.contains(delaySeconds) ? delaySeconds : 0
            if normalized != delaySeconds { delaySeconds = normalized }
            preferences.set(normalized, forKey: "captureDelaySeconds")
        }
    }
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var pendingMode: CaptureMode?
    @Published private(set) var lastCapturePixels = CGSize.zero
    @Published private(set) var shortcuts: [CaptureMode: CaptureShortcut] = [:]
    var onCapture: ((NSImage) -> Void)?
    /// Receives a native bitmap for one-step styled clipboard capture, without opening the editor.
    var onCaptureForClipboard: ((NSImage) -> Void)?
    /// Invoked after the capture is complete so the app can recreate a closed editor window.
    var onShowEditor: (() -> Void)?

    private var hotKeys: [CaptureMode: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var captureProcess: Process?
    private var captureTask: Task<Void, Never>?
    private var activeCaptureID: UUID?
    private var captureCancelled = false
    private var clipboardOnly = false
    private var hiddenWindows: [NSWindow] = []
    private let preferences: UserDefaults
    private let screenAccess: () -> Bool
    private let requestScreenAccess: () -> Bool
    private let signature: OSType = 0x534E4452 // SNDR

    override convenience init() { self.init(preferences: .standard) }

    init(preferences: UserDefaults, screenAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         requestScreenAccess: @escaping () -> Bool = { CGRequestScreenCaptureAccess() }) {
        self.preferences = preferences
        self.screenAccess = screenAccess
        self.requestScreenAccess = requestScreenAccess
        super.init()
        let delay = preferences.integer(forKey: "captureDelaySeconds")
        delaySeconds = Self.supportedDelays.contains(delay) ? delay : 0
        for mode in CaptureMode.allCases {
            let stored = preferences.data(forKey: "captureShortcut.\(mode.rawValue)")
            shortcuts[mode] = stored.flatMap { try? JSONDecoder().decode(CaptureShortcut.self, from: $0) } ?? Self.defaultShortcut(for: mode)
        }
    }

    private static func defaultShortcut(for mode: CaptureMode) -> CaptureShortcut {
        let key: UInt32
        switch mode { case .region: key = UInt32(kVK_ANSI_4); case .window: key = UInt32(kVK_ANSI_5); case .fullscreen: key = UInt32(kVK_ANSI_3) }
        return CaptureShortcut(keyCode: key, modifiers: UInt32(controlKey | optionKey | cmdKey))
    }

    func shortcutDisplay(for mode: CaptureMode) -> String { shortcuts[mode]?.display ?? "" }

    func installGlobalShortcuts() {
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let opaque = Unmanaged.passUnretained(self).toOpaque()
            let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var key = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
                guard result == noErr, key.signature == OSType(0x534E4452) else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<CaptureService>.fromOpaque(userData).takeUnretainedValue()
                let index = Int(key.id) - 1
                guard CaptureMode.allCases.indices.contains(index) else { return OSStatus(eventNotHandledErr) }
                let mode = CaptureMode.allCases[index]
                Task { @MainActor in service.capture(mode) }
                return noErr
            }, 1, &spec, opaque, &eventHandler)
            guard result == noErr else { status = "Could not install global screenshot shortcuts (\(result)). Capture is available from the menu."; return }
        }
        for mode in CaptureMode.allCases { _ = register(mode) }
    }

    /// Use macOS virtual key codes and Carbon modifiers. Existing binding is retained if the new one conflicts.
    @discardableResult
    func updateShortcut(for mode: CaptureMode, keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            status = "Add Command, Control, or Option to a global shortcut."
            return false
        }
        let proposed = CaptureShortcut(keyCode: keyCode, modifiers: modifiers)
        guard !shortcuts.contains(where: { $0.key != mode && $0.value == proposed }) else {
            status = "That shortcut is already assigned to another capture mode."
            return false
        }
        let original = shortcuts[mode]
        shortcuts[mode] = proposed
        guard register(mode) else {
            shortcuts[mode] = original
            _ = register(mode)
            status = "That shortcut is used by macOS or another app. Choose another combination."
            return false
        }
        if let encoded = try? JSONEncoder().encode(proposed) { preferences.set(encoded, forKey: "captureShortcut.\(mode.rawValue)") }
        status = "\(mode.title): \(proposed.display)"
        return true
    }

    func resetShortcuts() {
        for reference in hotKeys.values { UnregisterEventHotKey(reference) }
        hotKeys.removeAll()
        for mode in CaptureMode.allCases {
            shortcuts[mode] = Self.defaultShortcut(for: mode)
            preferences.removeObject(forKey: "captureShortcut.\(mode.rawValue)")
        }
        installGlobalShortcuts()
    }

    private func register(_ mode: CaptureMode) -> Bool {
        if let existing = hotKeys.removeValue(forKey: mode) { UnregisterEventHotKey(existing) }
        guard let shortcut = shortcuts[mode], let index = CaptureMode.allCases.firstIndex(of: mode) else { return false }
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: signature, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &reference)
        if result == noErr, let reference { hotKeys[mode] = reference; return true }
        status = "\(mode.title) shortcut \(shortcut.display) is unavailable. Capture is available from the menu."
        return false
    }

    func capture(_ mode: CaptureMode) {
        beginCapture(mode, clipboardOnly: false)
    }

    func captureAndCopy(_ mode: CaptureMode) {
        beginCapture(mode, clipboardOnly: true)
    }

    private func beginCapture(_ mode: CaptureMode, clipboardOnly: Bool) {
        guard !busy else { return }
        guard ensureScreenAccess() else {
            return
        }
        busy = true
        pendingMode = mode
        self.clipboardOnly = clipboardOnly
        captureCancelled = false
        let captureID = UUID()
        activeCaptureID = captureID
        // Snapshot these settings: changing the picker while counting down applies to the next capture.
        let delay = delaySeconds
        remainingSeconds = delay
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                if delay > 0 {
                    for remaining in stride(from: delay, through: 1, by: -1) {
                        try Task.checkCancellation()
                        self.remainingSeconds = remaining
                        self.status = "\(mode.title) in \(remaining)s… Cancel to stop."
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
                try Task.checkCancellation()
                guard self.activeCaptureID == captureID else { return }
                self.remainingSeconds = 0
                self.status = mode == .fullscreen ? "Capturing the main display…" : "Drag to select. Press Space for a window, or Escape to cancel."
                self.hiddenWindows = NSApp.windows.filter { $0.isVisible && $0.level == .normal }
                self.hiddenWindows.forEach { $0.orderOut(nil) }
                try await Task.sleep(nanoseconds: 250_000_000)
                try Task.checkCancellation()
                guard self.activeCaptureID == captureID else { return }
                self.startCaptureProcess(mode, captureID: captureID)
            } catch {
                guard self.activeCaptureID == captureID else { return }
                self.finishCapture(status: "Capture cancelled", captureID: captureID)
            }
        }
    }

    /// Denial must never create a prompt loop, including after relaunch. Always recheck
    /// the real OS grant so enabling access takes effect without resetting preferences.
    @discardableResult func ensureScreenAccess() -> Bool {
        if screenAccess() { needsScreenPermission = false; return true }
        if !preferences.bool(forKey: "screenAccessRequested") {
            preferences.set(true, forKey: "screenAccessRequested")
            if requestScreenAccess() { needsScreenPermission = false; return true }
        }
        needsScreenPermission = true
        status = "Screen Recording needs a restart after access changes. Quit and reopen Sanju's SnapDrive; image opening still works."
        return false
    }

    private func startCaptureProcess(_ mode: CaptureMode, captureID: UUID) {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("SnapDrive-capture-\(UUID().uuidString).png")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            switch mode {
            case .region: task.arguments = ["-i", "-x", "-t", "png", destination.path]
            case .window: task.arguments = ["-i", "-W", "-o", "-x", "-t", "png", destination.path]
            case .fullscreen: task.arguments = ["-m", "-x", "-t", "png", destination.path]
            }
            task.standardError = FileHandle.nullDevice
            self.captureProcess = task
            task.terminationHandler = { [weak self] process in
                let success = process.terminationStatus == 0
                Task { @MainActor in
                    guard let self else { try? FileManager.default.removeItem(at: destination); return }
                    guard self.activeCaptureID == captureID else { try? FileManager.default.removeItem(at: destination); return }
                    defer {
                        try? FileManager.default.removeItem(at: destination)
                        self.finishCapture(captureID: captureID)
                    }
                    if self.captureCancelled { self.status = "Capture cancelled" }
                    else if success, let image = try? Self.loadCapturedImage(at: destination) {
                        self.deliverCapturedImage(image, clipboardOnly: self.clipboardOnly)
                    } else if mode == .fullscreen {
                        self.status = "Capture failed. Check Screen Recording access in System Settings."
                    } else {
                        self.status = "Capture cancelled"
                    }
                }
            }
            do { try task.run() }
            catch {
                self.finishCapture(status: "Could not start capture: \(error.localizedDescription)", captureID: captureID)
                try? FileManager.default.removeItem(at: destination)
            }
    }

    /// Decode before deleting the temporary file and retain its full native bitmap and DPI metadata.
    /// The screenshot is never redrawn at NSImage.size, which may be half the native size on Retina.
    static func loadCapturedImage(at url: URL) throws -> NSImage {
        let data = try Data(contentsOf: url)
        guard let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else {
            throw NSError(domain: "SnapDrive.Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "The screenshot could not be decoded."])
        }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    /// Kept independent of screen access so bitmap preservation and callback routing can be checked offline.
    func deliverCapturedImage(_ image: NSImage, clipboardOnly: Bool) {
        if let bitmap = image.representations.first as? NSBitmapImageRep {
            lastCapturePixels = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            status = "Captured \(bitmap.pixelsWide) × \(bitmap.pixelsHigh) native pixels"
        }
        if clipboardOnly {
            if let onCaptureForClipboard { onCaptureForClipboard(image) }
            else {
                NSPasteboard.general.clearContents()
                if NSPasteboard.general.writeObjects([image]) { status = "Screenshot copied" }
                else { status = "The screenshot could not be copied to the clipboard." }
            }
        } else {
            onCapture?(image)
            onShowEditor?()
        }
    }

    private func finishCapture(status message: String? = nil, captureID: UUID) {
        guard activeCaptureID == captureID else { return }
        if let message { status = message }
        remainingSeconds = 0
        pendingMode = nil
        busy = false
        captureTask = nil
        captureProcess = nil
        activeCaptureID = nil
        let windows = hiddenWindows
        hiddenWindows = []
        windows.forEach { $0.makeKeyAndOrderFront(nil) }
        if !windows.isEmpty { NSApp.activate(ignoringOtherApps: true) }
    }

    func cancelCapture() {
        guard busy, let captureID = activeCaptureID else { return }
        captureCancelled = true
        captureTask?.cancel()
        if let captureProcess, captureProcess.isRunning { captureProcess.terminate() }
        else { finishCapture(status: "Capture cancelled", captureID: captureID) }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }

    func uninstallGlobalShortcuts() {
        for reference in hotKeys.values { UnregisterEventHotKey(reference) }
        hotKeys.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
    }
}
