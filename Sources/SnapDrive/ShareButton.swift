import SwiftUI
import AppKit

struct ShareButton: NSViewRepresentable {
    var image: NSImage?
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.up.on.square", accessibilityDescription: "Share image")!, target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .texturedRounded; button.toolTip = "Share edited screenshot"; return button
    }
    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.image = image; button.isEnabled = image != nil }
    final class Coordinator: NSObject {
        var image: NSImage?
        @objc func share(_ sender: NSButton) { guard let image else { return }; let picker = NSSharingServicePicker(items: [image]); picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY) }
    }
}

@MainActor enum SharePresenter {
    static func present(_ image: NSImage?) {
        guard let image, let host = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: NSRect(x: host.bounds.maxX-100, y: host.bounds.maxY-40, width: 20, height: 20), of: host, preferredEdge: .minY)
    }
}
