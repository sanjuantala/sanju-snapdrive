import AppKit
import ImageIO

struct BackgroundAsset: Identifiable {
    var id: String; var name: String; var photograph = false
}
@MainActor enum BackgroundLibrary {
    static let assets: [BackgroundAsset] = [
        .init(id: "dunes", name: "Dawn Dunes", photograph: true),
        .init(id: "coast", name: "Quiet Coast", photograph: true),
        .init(id: "mist", name: "Alpine Mist", photograph: true),
        .init(id: "ribbon", name: "Silk Ribbon"),
        .init(id: "mesh", name: "Pastel Mesh"),
        .init(id: "midnight", name: "Midnight"),
        .init(id: "sage", name: "Sage Paper"),
        .init(id: "pearl", name: "Pearl"),
        .init(id: "ember", name: "Ember")
    ]
    // Keep one native export backdrop, a few bounded editing previews, and tiny picker thumbnails.
    private static let fullCache: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 1; c.totalCostLimit = 48_000_000; return c }()
    private static let previewCache: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 3; c.totalCostLimit = 24_000_000; return c }()
    private static let thumbCache: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 16; c.totalCostLimit = 3_000_000; return c }()
    static func clearCaches() { fullCache.removeAllObjects(); previewCache.removeAllObjects(); thumbCache.removeAllObjects() }
    static func url(for id: String) -> URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Backgrounds/\(id).png")
        #if SNAPDRIVE_BUNDLED_ASSETS
        let candidates = [bundled]
        #else
        let candidates = [bundled, URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Backgrounds/\(id).png")]
        #endif
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func image(_ id: String) -> NSImage? {
        guard let asset = assets.first(where: { $0.id == id }) else { return nil }
        if let image = fullCache.object(forKey: id as NSString) { return image }
        let image = asset.photograph ? url(for: id).flatMap { NSImage(contentsOf: $0) } : procedural(id, width: 3840, height: 2400)
        if let image { let px = ImageEngine.pixelSize(image); fullCache.setObject(image, forKey: id as NSString, cost: Int(px.width*px.height*4)) }
        return image
    }
    static func thumbnail(_ id: String) -> NSImage? {
        if let image = thumbCache.object(forKey: id as NSString) { return image }
        let image: NSImage?
        if let asset = assets.first(where: { $0.id == id }), asset.photograph, let url = url(for: id), let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 320, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) { image = ImageEngine.bitmapImage(cgImage:cg) }
        else { image = procedural(id,width: 320,height: 200) }
        if let image { let pixels = ImageEngine.pixelSize(image); thumbCache.setObject(image, forKey: id as NSString,cost: Int(pixels.width*pixels.height*4)) }; return image
    }
    /// Editing reads a small photo thumbnail or renders procedural artwork directly at preview size.
    /// image(_:) remains independent and supplies the original/native backdrop for export.
    static func previewImage(_ id: String, maxPixelDimension: Int = 1800) -> NSImage? {
        guard let asset = assets.first(where: { $0.id == id }) else { return nil }
        let limit = min(2400,max(64,maxPixelDimension))
        let key = "\(id):\(limit)" as NSString
        if let cached = previewCache.object(forKey:key) { return cached }
        let image: NSImage?
        if asset.photograph {
            guard let url = url(for:id),let source = CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:limit,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { return nil }
            image = ImageEngine.bitmapImage(cgImage:cg)
        } else { image = procedural(id,width:limit,height:max(1,Int(Double(limit)*2400/3840))) }
        if let image { let pixels = ImageEngine.pixelSize(image); previewCache.setObject(image,forKey:key,cost:Int(pixels.width*pixels.height*4)) }
        return image
    }
    private static func procedural(_ id: String, width: Int, height: Int) -> NSImage? {
        guard let ctx = CGContext(data: nil,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width*4,space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let palettes: [String:[String]] = ["ribbon":["#413586","#A598EA","#EFC2E8"],"mesh":["#D9EAF2","#E4D4F1","#F5DAC7"],"midnight":["#071827","#176780","#5366B9"],"sage":["#B9CABC","#DEE8CD","#91B1AC"],"pearl":["#E4E4ED","#F9EFF3","#B7B4D9"],"ember":["#632E58","#EA8C73","#F6CE8D"]]
        guard let p = palettes[id] else { return nil }
        let colors = p.map { ImageEngine.color(hex: $0).cgColor }
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),colors: colors as CFArray,locations: [0,0.52,1])!
        ctx.drawLinearGradient(gradient,start: .zero,end: CGPoint(x: width,y: height),options: [.drawsBeforeStartLocation,.drawsAfterEndLocation])
        let scale = Double(width)/3840
        if id == "ribbon" || id == "pearl" || id == "ember" {
            for i in 0..<5 {
                let shift = Double(i)*420*scale
                let path = CGMutablePath(); path.move(to: CGPoint(x: -500*scale,y: shift-180*scale))
                path.addCurve(to: CGPoint(x: Double(width)+500*scale,y: Double(height)-shift+260*scale),control1: CGPoint(x: 1400*scale,y: Double(height)+shift),control2: CGPoint(x: 1800*scale,y: -shift))
                ctx.addPath(path); ctx.setLineWidth(90*scale); ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor); ctx.setShadow(offset: CGSize(width: 0,height: -15*scale),blur: 55*scale,color: NSColor.black.withAlphaComponent(0.12).cgColor); ctx.strokePath()
            }; ctx.setShadow(offset: .zero,blur: 0,color: nil)
        } else {
            for (x,y,r,c) in [(0.15,0.8,0.85,0),(0.85,0.12,0.9,1),(0.45,0.45,0.75,2)] {
                let color = NSColor(cgColor: colors[c])!
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),colors: [color.withAlphaComponent(0.65).cgColor,color.withAlphaComponent(0).cgColor] as CFArray,locations: [0,1])!
                let center = CGPoint(x: Double(width)*x,y: Double(height)*y)
                ctx.drawRadialGradient(g,startCenter: center,startRadius: 0,endCenter: center,endRadius: Double(width)*r,options: [])
            }
        }
        // Fine deterministic paper grain: native 4K artwork rather than a resized thumbnail.
        var seed: UInt64 = 314159
        for _ in 0..<(id == "sage" ? width*height/90 : width*height/160) {
            seed = seed &* 6364136223846793005 &+ 1; let x = Int((seed >> 32) % UInt64(width))
            seed = seed &* 6364136223846793005 &+ 1; let y = Int((seed >> 32) % UInt64(height))
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.045).cgColor); ctx.fill(CGRect(x: x,y: y,width: 1,height: 1))
        }
        guard let cg = ctx.makeImage() else { return nil }; return ImageEngine.bitmapImage(cgImage:cg)
    }
}
