import AppKit

@main struct WindowChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        WindowChromeView.configure(window)
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        assert(buttons.count == 3)
        WindowChromeView.configure(window)
        assert(zip(buttons,[NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]).allSatisfy { $0.0 === window.standardWindowButton($0.1) }, "Repeated configuration must retain the same native controls")
        for button in buttons { assert(!button.isHidden && button.isEnabled && button.frame.width > 0) }
        assert(window.styleMask.contains([.titled, .closable, .miniaturizable, .resizable]))
        assert(window.collectionBehavior.contains(.fullScreenPrimary) && window.titleVisibility == .visible)
        assert(buttons[0].frame.maxX < buttons[1].frame.minX && buttons[1].frame.maxX < buttons[2].frame.minX)
        print("PASS native window chrome: visible enabled close/minimize/full-screen controls, title, resizable titled window, no duplicate content controls")
    }
}
