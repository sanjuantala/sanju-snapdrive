import SwiftUI
import AppKit

@MainActor final class AppServices {
    static let shared = AppServices()
    let model = EditorModel()
    let capture = CaptureService()
    let drive = DriveService()
    let clipboardPreview = ClipboardCapturePreview()
    var reopen: (() -> Void)?
    var configured = false
    private var lastOpenedFile: (url: URL, time: TimeInterval)?
    func configure() {
        guard !configured else { return }; configured = true
        model.restoreBackground()
        capture.onCaptureStarted = { [weak self] in self?.clipboardPreview.hide() }
        capture.onCapture = { [weak self] image in
            guard let self else { return }
            self.model.load(image, captured: true, window: self.capture.pendingMode == .window)
        }
        capture.onCaptureForClipboard = { [weak self] image in
            guard let self else { return }
            let prepared = self.model.captureAppearance(image, window: self.capture.pendingMode == .window)
            if let rendered = ImageEngine.render(image: prepared.image, style: prepared.style, annotations: [], backgroundImage: self.model.activeBackgroundImage), let data = ImageEngine.data(image: rendered, format: "png", quality: 1) {
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setData(data, forType: .png) else {
                    self.capture.status = "Could not copy the screenshot"; return
                }
                self.capture.status = "Screenshot copied as lossless PNG"
                self.clipboardPreview.show(image: rendered) { [weak self] in
                    guard let self else { return }
                    self.showEditor()
                    self.model.load(prepared.image, appearance: prepared.style, notifyNewImage: false)
                }
            } else { self.capture.status = "Could not render capture for clipboard" }
        }
        capture.onShowEditor = { [weak self] in self?.showEditor() }
        model.onNewImage = { [weak self] in guard let self, self.drive.autoUpload else { return }; self.model.saveDrive(self.drive, automatic: true) }
        capture.installGlobalShortcuts()
    }
    func showEditor() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Sanju's SnapDrive" && $0.canBecomeMain }) { window.makeKeyAndOrderFront(nil) }
        else { reopen?() }
    }
    func openImage(_ url: URL) {
        guard url.isFileURL else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let target = url.standardizedFileURL
        // Modern SwiftUI and legacy document events can describe the same handoff.
        if let lastOpenedFile, lastOpenedFile.url == target && now - lastOpenedFile.time < 1 { return }
        lastOpenedFile = (target, now)
        configure(); showEditor(); model.open(url)
    }
}

@main struct SnapDriveApp: App {
    @NSApplicationDelegateAdaptor(SnapDriveDelegate.self) var delegate
    @StateObject var model = AppServices.shared.model
    @StateObject var capture = AppServices.shared.capture
    @StateObject var drive = AppServices.shared.drive
    var body: some Scene {
        Window("Sanju's SnapDrive", id: "editor") {
            AppRoot().environmentObject(model).environmentObject(capture).environmentObject(drive)
        }
        .defaultSize(width: 1240, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .commands { SnapDriveCommands(model: model, capture: capture, drive: drive) }
        Settings { DriveSettings().environmentObject(model).environmentObject(capture).environmentObject(drive) }
    }
}

struct AppRoot: View {
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var model: EditorModel
    @EnvironmentObject var capture: CaptureService
    var body: some View {
        EditorView()
            .background(WindowChrome().frame(width: 0, height: 0))
            .onAppear {
                AppServices.shared.reopen = { openWindow(id: "editor") }
                AppServices.shared.configure()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.keyWindow?.makeFirstResponder(nil) }
                if let flag = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.count > flag + 1, model.image == nil { model.open(URL(fileURLWithPath: CommandLine.arguments[flag+1])) }
            }
            .onChange(of: capture.status) { status in model.status = status }
            .onOpenURL { AppServices.shared.openImage($0) }
    }
}

@MainActor final class SnapDriveDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppServices.shared.configure()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Sanju's SnapDrive")
        let menu = NSMenu()
        add("Open Sanju's SnapDrive", #selector(showEditor), to: menu)
        menu.addItem(.separator())
        add("Capture Region", #selector(region), to: menu)
        add("Capture Window", #selector(window), to: menu)
        add("Capture Full Screen", #selector(fullscreen), to: menu)
        add("Capture Region & Copy", #selector(captureCopy), to: menu)
        menu.addItem(.separator())
        add("Open Image…", #selector(openImage), to: menu)
        add("Paste Image", #selector(pasteImage), to: menu)
        add("Screenshot History", #selector(history), to: menu)
        add("Google Drive Settings…", #selector(settings), to: menu)
        menu.addItem(.separator())
        add("Quit Sanju's SnapDrive", #selector(quit), to: menu)
        item.menu = menu; statusItem = item

    }
    func add(_ title: String, _ action: Selector, to menu: NSMenu) { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { AppServices.shared.showEditor(); return true }
    func applicationWillTerminate(_ notification: Notification) { AppServices.shared.model.commitActiveText(); AppServices.shared.model.persistCurrent(); AppServices.shared.capture.cancelCapture(); AppServices.shared.capture.uninstallGlobalShortcuts() }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { if let first = filenames.first { AppServices.shared.openImage(URL(fileURLWithPath: first)) }; sender.reply(toOpenOrPrint: .success) }
    func application(_ application: NSApplication, open urls: [URL]) { if let first = urls.first { AppServices.shared.openImage(first) } }
    @objc func showEditor() { AppServices.shared.showEditor() }
    @objc func region() { AppServices.shared.capture.capture(.region) }
    @objc func window() { AppServices.shared.capture.capture(.window) }
    @objc func fullscreen() { AppServices.shared.capture.capture(.fullscreen) }
    @objc func captureCopy() { AppServices.shared.capture.captureAndCopy(.region) }
    @objc func openImage() { showEditor(); AppServices.shared.model.open() }
    @objc func pasteImage() { showEditor(); AppServices.shared.model.paste() }
    @objc func history() { showEditor(); AppServices.shared.model.showHistory = true }
    @objc func settings() { showEditor(); AppServices.shared.model.showDrive = true }
    @objc func quit() { NSApp.terminate(nil) }
}

struct SnapDriveCommands: Commands {
    @ObservedObject var model: EditorModel
    @ObservedObject var capture: CaptureService
    @ObservedObject var drive: DriveService
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Capture Region") { capture.capture(.region) }
            Button("Capture Window") { capture.capture(.window) }
            Button("Capture Full Screen") { capture.capture(.fullscreen) }
            Button("Capture Region & Copy") { capture.captureAndCopy(.region) }
            Divider()
            Button("Open Image…") { model.open() }.keyboardShortcut("o")
            Button("Paste Image") { model.paste() }.keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Export…") { model.save() }.keyboardShortcut("s").disabled(model.image == nil)
            Button("Upload & Copy Drive Link") { model.uploadAndCopy(drive) }.keyboardShortcut("u", modifiers: [.command, .shift]).disabled(model.image == nil || model.busy)
            Button("Save to Google Drive") { model.saveDrive(drive) }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model.image == nil || model.busy)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Edit") { if let field = NSApp.keyWindow?.firstResponder as? NSTextView, let undo = field.undoManager { undo.undo() } else { model.undo() } }.keyboardShortcut("z")
            Button("Redo Edit") { if let field = NSApp.keyWindow?.firstResponder as? NSTextView, let undo = field.undoManager { undo.redo() } else { model.redo() } }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In") { model.requestZoom("in") }.keyboardShortcut("=").disabled(model.image == nil)
            Button("Zoom Out") { model.requestZoom("out") }.keyboardShortcut("-").disabled(model.image == nil)
            Button("Fit Screenshot to Window") { model.requestZoom("fit") }.keyboardShortcut("0").disabled(model.image == nil)
            Button("Actual Pixels · 100%") { model.requestZoom("actual") }.keyboardShortcut("1").disabled(model.image == nil)
            Divider()
            Button("Keyboard Shortcuts…") { model.commitActiveText(); model.showShortcuts = true }.keyboardShortcut("/")
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { (NSApp.keyWindow?.firstResponder as? NSTextView)?.cut(nil) }.keyboardShortcut("x")
            Button("Copy") { if let field = NSApp.keyWindow?.firstResponder as? NSTextView { field.copy(nil) } else { model.copyImage() } }.keyboardShortcut("c")
            Button("Paste") { if let field = NSApp.keyWindow?.firstResponder as? NSTextView { field.paste(nil) } else { model.paste() } }.keyboardShortcut("v")
            Button("Select All") { (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil) }.keyboardShortcut("a")
            Divider()
            Button("Copy Edited Image") { model.copyImage() }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(model.image == nil)
            Button("Copy Text from Image") { model.recognize(copy: true) }.disabled(model.image == nil)
            Button("Delete Selected Annotation") { model.removeSelected() }.disabled(model.selectedID == nil)
            Button("Clear Screenshot") { model.clearCanvas() }.disabled(model.image == nil)
            Button("Clear All Annotations") { model.clearAnnotations() }.disabled(model.image == nil)
        }
        CommandMenu("Image") {
            ForEach(EditorTool.allCases, id: \.self) { tool in Button(tool.title) { NotificationCenter.default.post(name: .snapDriveFocusCanvas, object: nil); if tool != .select { model.selectAnnotation(nil) }; model.tool = tool } }
            Divider()
            Button("Balance Content") { model.balance() }.disabled(model.image == nil)
            Button("Redact Sensitive Data") { model.recognize(redact: true) }.disabled(model.image == nil)
            Button("Screenshot History…") { model.showHistory = true }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Google Drive Settings…") { model.showDrive = true }
            Divider()
            Button("Browser Extension…") { BrowserBridge.showSetup() }
        }
    }
}
