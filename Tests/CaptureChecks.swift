import AppKit
import Foundation

@main struct CaptureChecks {
    @MainActor static func main() throws {
        let suite = "SnapDriveCaptureChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(999, forKey: "captureDelaySeconds")
        let service = CaptureService(preferences: defaults)
        assert(service.delaySeconds == 0)
        for delay in CaptureService.supportedDelays {
            service.delaySeconds = delay
            assert(defaults.integer(forKey: "captureDelaySeconds") == delay)
            assert(CaptureService(preferences: defaults).delaySeconds == delay)
        }
        service.delaySeconds = 6
        assert(service.delaySeconds == 0 && defaults.integer(forKey: "captureDelaySeconds") == 0)
        service.cancelCapture()
        assert(!service.busy && service.remainingSeconds == 0 && service.pendingMode == nil)
        var access = false, requests = 0
        let permissionService = CaptureService(preferences: defaults, screenAccess: { access }, requestScreenAccess: { requests += 1; return false })
        for _ in 0..<5 { permissionService.capture(.region) }
        assert(requests == 1 && permissionService.needsScreenPermission && !permissionService.busy)
        let relaunched = CaptureService(preferences: defaults, screenAccess: { access }, requestScreenAccess: { requests += 1; return false })
        assert(!relaunched.ensureScreenAccess() && requests == 1, "Denied access must not re-prompt after relaunch")
        access = true
        assert(relaunched.ensureScreenAccess() && !relaunched.needsScreenPermission && requests == 1, "Recheck OS grant after Settings changes")
        defaults.removeObject(forKey: "screenAccessRequested")
        let newlyGranted = CaptureService(preferences: defaults, screenAccess: { false }, requestScreenAccess: { true })
        assert(newlyGranted.ensureScreenAccess() && !newlyGranted.needsScreenPermission)
        let context = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 1600, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<400 {
            context.setFillColor(CGColor(red: x % 2 == 0 ? 1 : 0, green: 0, blue: x % 2 == 0 ? 0 : 1, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: 200))
        }
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        bitmap.size = NSSize(width: 200, height: 100)
        let encoded = bitmap.representation(using: .png, properties: [:])!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try encoded.write(to: url)
        let result = try CaptureService.loadCapturedImage(at: url)
        try FileManager.default.removeItem(at: url)
        let decoded = result.representations.first as! NSBitmapImageRep
        assert(decoded.pixelsWide == 400 && decoded.pixelsHigh == 200)
        assert(abs(result.size.width - 200) < 0.1 && abs(result.size.height - 100) < 0.1, "Retina logical size / DPI must survive")
        assert(decoded.colorAt(x: 100,y: 75)!.usingColorSpace(.deviceRGB)!.redComponent > 0.9)
        assert(decoded.colorAt(x: 101,y: 75)!.usingColorSpace(.deviceRGB)!.blueComponent > 0.9, "Single-pixel stripe detail must survive without scaling")
        var editorCaptures = 0, clipboardCaptures = 0, editorOpens = 0
        service.onCapture = { incoming in assert(incoming === result); editorCaptures += 1 }
        service.onCaptureForClipboard = { incoming in assert(incoming === result); clipboardCaptures += 1 }
        service.onShowEditor = { editorOpens += 1 }
        service.deliverCapturedImage(result, clipboardOnly: true)
        assert(clipboardCaptures == 1 && editorCaptures == 0 && editorOpens == 0, "Copy-only capture must not open or load the editor")
        service.deliverCapturedImage(result, clipboardOnly: false)
        assert(editorCaptures == 1 && editorOpens == 1 && clipboardCaptures == 1, "Normal capture must load and reveal the editor")
        assert(service.lastCapturePixels == CGSize(width: 400, height: 200))
        print("PASS permission prompt-once including relaunch, grant recheck, capture delay normalization/persistence, idle cancellation, Retina native-pixel and DPI preservation, one-pixel detail after temporary-file deletion, clipboard/editor routing")
    }
}
