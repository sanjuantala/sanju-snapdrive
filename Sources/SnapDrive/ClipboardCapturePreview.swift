import AppKit
import SwiftUI

/// The copied screenshot is ready to paste immediately. This card never takes keyboard focus.
@MainActor
final class ClipboardCapturePreview {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(image: NSImage, edit: @escaping @MainActor () -> Void) {
        hide()
        let width: CGFloat = 326
        let height: CGFloat = 94
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let window = NSPanel(
            contentRect: NSRect(x: area.maxX - width - 18, y: area.minY + 18, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.title = "SnapDrive capture preview"
        window.contentView = NSHostingView(rootView: ClipboardCaptureCard(
            image: image,
            edit: { [weak self] in self?.hide(); edit() },
            dismiss: { [weak self] in self?.hide() }
        ).frame(width: width, height: height))
        panel = window
        window.orderFrontRegardless()
        dismissal = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            self?.hide()
        }
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct ClipboardCaptureCard: View {
    let image: NSImage
    let edit: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(width: 64, height: 61)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Label("Screenshot copied", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Ready to paste with ⌘V").font(.system(size: 10)).foregroundStyle(.secondary)
                Button("Edit in Mac App", action: edit)
                    .controlSize(.small).buttonStyle(.borderedProminent).tint(.indigo)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
            }.buttonStyle(.borderless).accessibilityLabel("Dismiss capture preview")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.secondary.opacity(0.25)))
    }
}
