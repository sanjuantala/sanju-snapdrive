import AppKit

/// User-invoked setup only. Browser screenshots arrive through the normal image-opening route.
@MainActor enum BrowserBridge {
    static let extensionID = "onchblaldmgmldajccljklnjonkicpnf"
    static let hostName = "com.snapdrive.browser"

    static func install(bundle: Bundle = .main, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        guard let root = bundle.resourceURL?.appendingPathComponent("BrowserExtension"), FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path) else {
            throw NSError(domain: hostName, code: 1, userInfo: [NSLocalizedDescriptionKey: "The browser extension is missing. Reinstall the latest app."])
        }
        let helper = bundle.bundleURL.appendingPathComponent("Contents/Helpers/SnapDriveBrowserHost")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw NSError(domain: hostName, code: 2, userInfo: [NSLocalizedDescriptionKey: "The browser connection is missing. Reinstall the latest app."])
        }
        let manifest: [String: Any] = ["name": hostName, "description": "Send browser screenshots to Sanju’s SnapDrive", "path": helper.path, "type": "stdio", "allowed_origins": ["chrome-extension://\(extensionID)/"]]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        for browser in ["Google/Chrome", "Microsoft Edge"] {
            let directory = home.appendingPathComponent("Library/Application Support/\(browser)/NativeMessagingHosts", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("\(hostName).json")
            try data.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        return root
    }

    static func showSetup() {
        let alert = NSAlert()
        do {
            let extensionFolder = try install()
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(extensionFolder.path, forType: .string)
            NSWorkspace.shared.activateFileViewerSelecting([extensionFolder])
            alert.messageText = "Your Mac connection is ready"
            alert.informativeText = "One-time setup for Chrome or Edge:\n\n1. Open chrome://extensions or edge://extensions.\n2. Turn on Developer mode, then choose Load unpacked.\n3. Select the BrowserExtension folder shown in Finder. Its path is copied; press ⌘⇧G in the folder picker and paste it.\n4. Pin Sanju’s SnapDrive, then choose Full page, Visible area, or Selected area.\n\nAlready installed? Click Reload on its extension card after updating the app. Full-page capture uses the temporary active-tab scripting permission.\n\nKeep this app in its final location. If you move it, run Browser Extension… again."
            alert.addButton(withTitle: "Done")
        } catch {
            alert.messageText = "Browser connection needs attention"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
        }
        alert.runModal()
    }
}
