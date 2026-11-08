import AppKit
import Foundation

@main
struct DriveChecks {
    @MainActor static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("SnapDrive-DriveChecks-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? manager.removeItem(at: root)
            UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        }
        func configuration(folder: String) {
            UserDefaults.standard.setVolatileDomain([
                "drive.oauth.clientID": "",
                "drive.syncFolder": folder,
                "drive.autoUpload": false
            ], forName: UserDefaults.argumentDomain)
        }
        configuration(folder: root.path)
        let service = DriveService()
        try require(!service.isConnected && !service.busy, "Folder mode must start without OAuth")
        try require(service.clientID.isEmpty && service.clientSecret.isEmpty, "No credentials should be needed")
        let original = Data("original screenshot bytes".utf8)
        let later = Data("later screenshot bytes".utf8)
        let first = try service.saveToSyncFolder(data: original, name: "Screenshot.png")
        let second = try service.saveToSyncFolder(data: later, name: "Screenshot.png")
        try require(first != second, "Same-name saves must have distinct destinations")
        try require(first.lastPathComponent == "Screenshot.png", "First save must retain requested filename")
        try require(second.pathExtension == "png", "Renamed files must preserve their extension")
        try require(try Data(contentsOf: first) == original, "Second save must not overwrite the first")
        try require(try Data(contentsOf: second) == later, "Second save must contain correct bytes")
        let safe = try service.saveToSyncFolder(data: later, name: "../../escaped-\(UUID().uuidString).png")
        try require(safe.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL, "A filename must never escape the destination folder")
        try require(try Data(contentsOf: safe) == later, "Sanitized filename must save correctly")
        try require(service.status.contains("Drive for desktop"), "Status must describe a local save rather than claiming confirmed cloud upload")
        configuration(folder: root.appendingPathComponent("missing-folder").path)
        let unavailable = DriveService()
        try expectFailure("Missing folder must fail clearly") { _ = try unavailable.saveToSyncFolder(data: original, name: "Screenshot.png") }
        try require(!manager.fileExists(atPath: root.appendingPathComponent("missing-folder").path), "Unavailable Drive locations must not be silently recreated")
        configuration(folder: "")
        let unconfigured = DriveService()
        try expectFailure("Unconfigured destination must fail clearly") { _ = try unconfigured.saveToSyncFolder(data: original, name: "Screenshot.png") }
        configuration(folder: first.path)
        let regularFile = DriveService()
        try expectFailure("A file must not be accepted as destination folder") { _ = try regularFile.saveToSyncFolder(data: original, name: "Screenshot.png") }
        try await DriveLinkChecks.run()
        try await DriveOAuthChecks.run()
        print("Drive checks passed: no-OAuth startup, writes, collision protection, safe filenames, unavailable/unconfigured destinations.")
    }

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CheckFailure(message) }
    }
    static func expectFailure(_ message: String, operation: () throws -> Void) throws {
        do { try operation() } catch { return }
        throw CheckFailure(message)
    }
    struct CheckFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
