import AppKit

@main struct BrowserSetupChecks {
    @MainActor static func main() throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("snapdrive-browser-setup-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temporary) }
        let app = temporary.appendingPathComponent("Sanju's SnapDrive.app")
        let contents = app.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources/BrowserExtension")
        let helpers = contents.appendingPathComponent("Helpers")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.createDirectory(at: helpers, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.snapdrive.browser.tests", "CFBundleName": "BrowserSetupChecks", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try Data("{}".utf8).write(to: resources.appendingPathComponent("manifest.json"))
        let helper = helpers.appendingPathComponent("SnapDriveBrowserHost")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        guard let bundle = Bundle(path: app.path) else { fatalError("Fixture bundle missing") }
        let fakeHome = temporary.appendingPathComponent("home")
        let folder = try BrowserBridge.install(bundle: bundle, home: fakeHome)
        precondition(folder.standardizedFileURL == resources.standardizedFileURL)
        for browser in ["Google/Chrome", "Microsoft Edge"] {
            let file = fakeHome.appendingPathComponent("Library/Application Support/\(browser)/NativeMessagingHosts/com.snapdrive.browser.json")
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            precondition(object["name"] as? String == "com.snapdrive.browser")
            precondition(object["path"] as? String == helper.path)
            precondition(object["type"] as? String == "stdio")
            precondition(object["allowed_origins"] as? [String] == ["chrome-extension://\(BrowserBridge.extensionID)/"])
            let attributes = try fm.attributesOfItem(atPath: file.path)
            precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        _ = try BrowserBridge.install(bundle: bundle, home: fakeHome)
        try fm.removeItem(at: helper)
        do { _ = try BrowserBridge.install(bundle: bundle, home: fakeHome); fatalError("Missing helper accepted") } catch {}
        print("PASS: Browser setup installs exact Chrome/Edge allowlist, absolute helper path, private file mode, repeat setup, missing-helper error")
    }
}
