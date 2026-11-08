import AppKit
import UniformTypeIdentifiers

/// One attached picker at a time; file-provider downloads happen off the UI thread.
@MainActor final class ImageImportService {
    private(set) var panel: NSOpenPanel?

    func choose(completion: @escaping (URL) -> Void) {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        let picker = NSOpenPanel()
        panel = picker
        picker.allowedContentTypes = [.image]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.message = "Choose a screenshot or image"
        picker.prompt = "Open image"
        NSApp.activate(ignoringOtherApps: true)
        let finished: (NSApplication.ModalResponse) -> Void = { [weak self, weak picker] response in
            let url = picker?.url
            self?.panel = nil
            if response == .OK, let url { completion(url) }
        }
        if let parent = NSApp.windows.first(where: { $0.identifier?.rawValue == "editor" && $0.isVisible && $0.attachedSheet == nil }) ?? NSApp.mainWindow,
           parent.attachedSheet == nil {
            picker.beginSheetModal(for: parent, completionHandler: finished)
        } else { picker.begin(completionHandler: finished) }
    }

    nonisolated static func decode(_ url: URL) throws -> NSImage {
        try decodeData(readData(url))
    }

    nonisolated static func decodeData(_ data: Data) throws -> NSImage {
        guard let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else {
            throw NSError(domain: "SnapDrive.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a supported image such as PNG, JPEG, TIFF, or HEIC."])
        }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    nonisolated static func readData(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            result = Result { try Data(contentsOf: readable) }
        }
        // Local files remain readable when the file-coordination daemon is unavailable
        // (for example in a restricted helper process). Preserve the real read error.
        if coordinationError != nil || result == nil { return try Data(contentsOf: url) }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
