import AppKit
import SwiftUI

struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowChromeView { WindowChromeView() }
    func updateNSView(_ view: WindowChromeView, context: Context) {}
}

final class WindowChromeView: NSView {
    private weak var configuredWindow: NSWindow?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, configuredWindow !== window { configuredWindow = window; Self.configure(window) }
    }

    static func configure(_ window: NSWindow) {
        let required: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if !window.styleMask.contains(required) { window.styleMask.formUnion(required) }
        if window.titleVisibility != .visible { window.titleVisibility = .visible }
        if window.toolbarStyle != .unifiedCompact { window.toolbarStyle = .unifiedCompact }
        if !window.collectionBehavior.contains(.fullScreenPrimary) { window.collectionBehavior.insert(.fullScreenPrimary) }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(kind) {
                if button.isHidden { button.isHidden = false }
                if !button.isEnabled { button.isEnabled = true }
            }
        }
    }
}
