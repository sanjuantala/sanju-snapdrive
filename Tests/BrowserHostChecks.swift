import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

@main struct BrowserHostChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; if !value { fputs("FAIL: \(message)\n", stderr); exit(1) } }
    static func rejects(_ message: String, _ block: () throws -> Void) { do { try block(); expect(false, message) } catch { expect(true, message) } }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snapdrive-browser-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pixels: [UInt8] = [110, 80, 220, 255, 50, 190, 160, 255]
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let encoded = NSMutableData()
        let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil); expect(CGImageDestinationFinalize(destination), "PNG fixture encodes")
        let png = encoded as Data
        let request: [String: Any] = ["version": 1, "action": "capture", "png": BrowserHostCore.pngPrefix + png.base64EncodedString()]
        expect(try BrowserHostCore.png(from: request) == png, "PNG retains every original byte")
        for bad in [[:], ["version": 2, "action": "capture", "png": request["png"]!], ["version": 1, "action": "execute", "png": request["png"]!], ["version": 1, "action": "capture", "png": "file:///etc/passwd"], ["version": 1, "action": "capture", "png": "data:image/jpeg;base64,AAAA"], ["version": 1, "action": "capture", "png": BrowserHostCore.pngPrefix + "%%%"], ["version": 1, "action": "capture", "png": BrowserHostCore.pngPrefix + Data("not png".utf8).base64EncodedString()], ["version": 1, "action": "capture", "png": BrowserHostCore.pngPrefix + png.prefix(32).base64EncodedString()]] as [[String: Any]] {
            rejects("Invalid or unsupported request rejected") { _ = try BrowserHostCore.png(from: bad) }
        }
        let payload = try JSONSerialization.data(withJSONObject: request)
        let framedFile = root.appendingPathComponent("input")
        var length = UInt32(payload.count).littleEndian
        let framed = withUnsafeBytes(of: &length) { Data($0) } + payload
        try framed.write(to: framedFile)
        let input = try FileHandle(forReadingFrom: framedFile); defer { try? input.close() }
        expect(try BrowserHostCore.readMessage(from: input) == payload, "Native request framing decodes exactly")
        for bytes in [Data(), Data([1]), Data([0, 0, 0, 0]), Data([255, 255, 255, 255]), Data([5, 0, 0, 0, 123])] {
            try bytes.write(to: framedFile)
            let stream = try FileHandle(forReadingFrom: framedFile)
            rejects("Invalid or truncated frame rejected") { _ = try BrowserHostCore.readMessage(from: stream) }
            try stream.close()
        }
        let response = try BrowserHostCore.response(["ok": true])
        let responseLength = response.prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
        expect(Int(responseLength) == response.count - 4, "Response uses native length prefix")
        expect(response.count < 1024 * 1024, "Response below browser 1MB limit")
        let cache = root.appendingPathComponent("cache")
        var opened: URL?
        let result = try BrowserHostCore.handle(payload, directory: cache) { opened = $0 }
        expect(result["ok"] as? Bool == true && opened != nil, "Valid capture opens in app")
        expect(try Data(contentsOf: opened!) == png, "Transferred capture remains original PNG")
        expect(opened!.lastPathComponent.hasPrefix("Browser-") && opened!.pathExtension == "png", "Generated filename ignores page input")
        let attributes = try FileManager.default.attributesOfItem(atPath: opened!.path)
        expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Capture file private to current user")
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: cache.path)
        expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "Capture cache private to current user")
        let countBefore = try FileManager.default.contentsOfDirectory(atPath: cache.path).count
        rejects("Failed app opening reported") { _ = try BrowserHostCore.handle(payload, directory: cache) { _ in throw BrowserHostCore.Failure.unavailable } }
        expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).count == countBefore, "Failed transfer removes partial handoff")
        for _ in 0..<25 { _ = try BrowserHostCore.store(png, directory: cache) }
        expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).count <= 20, "Capture cache bounded to 20 files")
        let other = cache.appendingPathComponent("unrelated.txt"); try Data([1]).write(to: other)
        _ = try BrowserHostCore.store(png, directory: cache, now: Date().addingTimeInterval(25 * 3600))
        expect(FileManager.default.fileExists(atPath: other.path), "Cleanup does not remove unrelated files")
        expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).filter { $0.hasPrefix("Browser-") }.count == 1, "Captures older than one day expire")
        rejects("Nonobject message rejected") { _ = try BrowserHostCore.handle(Data("[]".utf8), directory: cache) { _ in } }
        print("PASS: \(checks) browser native messaging checks")
    }
}
