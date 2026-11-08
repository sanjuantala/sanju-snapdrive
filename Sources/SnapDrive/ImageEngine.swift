import AppKit
import Accelerate
import Vision

enum AnnotationKind: String, Codable, CaseIterable, Hashable {
    case arrow, text, rectangle, ellipse, redact, pixelate, blur, magnifier
}

/// Shared by the live canvas, exported pixels and arrow hit testing.
struct ArrowGeometry {
    let start: CGPoint
    let shaftEnd: CGPoint
    let width: CGFloat
    let headLength: CGFloat
    let head: CGPath
}

/// Points are normalized against the original image, with (0, 0) at top left.
struct Annotation: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: AnnotationKind
    var start: CGPoint
    var end: CGPoint
    var text = ""
    var colorHex = "#FF5D73"
    var lineWidth = 5.0
    var fontSize = 28.0
    var magnification = 2.0

    init(id: UUID = UUID(), kind: AnnotationKind, start: CGPoint, end: CGPoint, text: String = "", colorHex: String = "#FF5D73", lineWidth: Double = 5, fontSize: Double = 28, magnification: Double = 2) {
        self.id = id; self.kind = kind; self.start = start; self.end = end; self.text = text
        self.colorHex = colorHex; self.lineWidth = lineWidth; self.fontSize = fontSize; self.magnification = magnification
    }
    private enum CodingKeys: String, CodingKey { case id, kind, start, end, text, colorHex, lineWidth, fontSize, magnification }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try values.decode(AnnotationKind.self, forKey: .kind)
        start = try values.decode(CGPoint.self, forKey: .start)
        end = try values.decode(CGPoint.self, forKey: .end)
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        colorHex = try values.decodeIfPresent(String.self, forKey: .colorHex) ?? "#FF5D73"
        lineWidth = try values.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 5
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 28
        magnification = try values.decodeIfPresent(Double.self, forKey: .magnification) ?? 2
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.start == rhs.start && lhs.end == rhs.end && lhs.text == rhs.text && lhs.colorHex == rhs.colorHex && lhs.lineWidth == rhs.lineWidth && lhs.fontSize == rhs.fontSize && lhs.magnification == rhs.magnification
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id); hasher.combine(kind)
        hasher.combine(start.x); hasher.combine(start.y); hasher.combine(end.x); hasher.combine(end.y)
        hasher.combine(text); hasher.combine(colorHex); hasher.combine(lineWidth); hasher.combine(fontSize); hasher.combine(magnification)
    }
}

struct EditorStyle: Codable, Equatable {
    var padding = 64.0
    var inset = 0.0
    var radius = 16.0
    var shadow = 28.0
    var background = "aurora"
    var solidHex = "#7371FC"
    /// Zero preserves the screenshot's natural aspect ratio.
    var ratio = 0.0
    var watermark = ""
    var exportScale = 1.0
    /// Backdrop blur in native output pixels; screenshot pixels are never blurred.
    var backgroundBlur = 0.0
    /// RGB multiplier for image backdrops. One keeps the original brightness.
    var backgroundBrightness = 1.0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case padding, inset, radius, shadow, background, solidHex, ratio, watermark, exportScale, backgroundBlur, backgroundBrightness
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        padding = try values.decodeIfPresent(Double.self, forKey: .padding) ?? 64
        inset = try values.decodeIfPresent(Double.self, forKey: .inset) ?? 0
        radius = try values.decodeIfPresent(Double.self, forKey: .radius) ?? 16
        shadow = try values.decodeIfPresent(Double.self, forKey: .shadow) ?? 28
        background = try values.decodeIfPresent(String.self, forKey: .background) ?? "aurora"
        solidHex = try values.decodeIfPresent(String.self, forKey: .solidHex) ?? "#7371FC"
        ratio = try values.decodeIfPresent(Double.self, forKey: .ratio) ?? 0
        watermark = try values.decodeIfPresent(String.self, forKey: .watermark) ?? ""
        exportScale = try values.decodeIfPresent(Double.self, forKey: .exportScale) ?? 1
        backgroundBlur = try values.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? 0
        backgroundBrightness = try values.decodeIfPresent(Double.self, forKey: .backgroundBrightness) ?? 1
    }
}

struct ImageSourceMetrics: Equatable {
    let pixelSize: CGSize
    let logicalSize: CGSize
    /// Pixels per logical point from file/NSImage metadata, not the current display.
    let nativeScale: Double
}

struct RecognizedLine {
    let text: String
    let rect: CGRect
}

enum ImageEngine {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private final class BackgroundCacheEntry: NSObject {
        weak var source: NSImage?
        let pixels: CGImage
        init(source: NSImage,pixels: CGImage) { self.source = source; self.pixels = pixels }
    }
    private static let backgroundCache: NSCache<NSString, BackgroundCacheEntry> = {
        let cache = NSCache<NSString, BackgroundCacheEntry>()
        cache.totalCostLimit = 32_000_000; cache.countLimit = 4
        return cache
    }()
    static func clearRenderingCaches() { backgroundCache.removeAllObjects() }

    static func cgImage(_ image: NSImage) -> CGImage? {
        // Prefer the full bitmap representation rather than its logical Retina size.
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }), let cg = bitmap.cgImage { return cg }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Keep native pixels in an explicit bitmap rep. NSCGImageSnapshotRep can choose a
    /// context-dependent raster size after the image has participated in AppKit drawing.
    static func bitmapImage(cgImage pixels: CGImage, logicalSize: CGSize? = nil) -> NSImage {
        var logical = logicalSize ?? CGSize(width:pixels.width,height:pixels.height)
        if !logical.width.isFinite || !logical.height.isFinite || logical.width <= 0 || logical.height <= 0 {
            logical = CGSize(width:pixels.width,height:pixels.height)
        }
        let representation = NSBitmapImageRep(cgImage:pixels)
        representation.size = logical
        let image = NSImage(size:logical)
        image.addRepresentation(representation)
        return image
    }

    /// Materialize imported/clipboard images before a view can influence their representation choice.
    /// Bitmap-backed input is already stable and can be reused without another full-size allocation.
    static func materializedImage(_ image: NSImage) -> NSImage? {
        if image.representations.contains(where: { $0 is NSBitmapImageRep }) { return image }
        guard let pixels = cgImage(image) else { return nil }
        return bitmapImage(cgImage:pixels,logicalSize:image.size)
    }

    static func pixelSize(_ image: NSImage) -> CGSize {
        guard let cg = cgImage(image) else {
            return CGSize(width: bounded(image.size.width, fallback: 1, lower: 1, upper: 40000), height: bounded(image.size.height, fallback: 1, lower: 1, upper: 40000))
        }
        return CGSize(width: cg.width, height: cg.height)
    }

    static func sourceMetrics(image: NSImage) -> ImageSourceMetrics {
        let pixels = pixelSize(image)
        var logical = image.size
        if !logical.width.isFinite || !logical.height.isFinite || logical.width <= 0 || logical.height <= 0 { logical = pixels }
        let x = pixels.width / logical.width, y = pixels.height / logical.height
        // Unusual non-square DPI metadata is not a Retina backing scale.
        let scale = abs(x - y) <= max(x,y) * 0.025 ? bounded((x+y)/2, fallback: 1, lower: 0.1, upper: 16) : 1
        return ImageSourceMetrics(pixelSize: pixels, logicalSize: logical, nativeScale: scale)
    }

    static func nativeScale(image: NSImage) -> Double { sourceMetrics(image: image).nativeScale }

    static func dimensions(image: NSImage, style: EditorStyle, maxPixelDimension: CGFloat? = nil) -> CGSize {
        let style = sanitized(style)
        let source = pixelSize(image)
        let border = max(0, style.padding) + max(0, style.inset)
        var width = source.width + border * 2
        var height = source.height + border * 2
        if style.ratio > 0.05 && style.ratio < 20 {
            if width / height < style.ratio { width = height * style.ratio }
            else { height = width / style.ratio }
        }
        let scale = min(4, max(0.1, style.exportScale))
        let full = CGSize(width: ceil(width * scale), height: ceil(height * scale))
        let factor = previewFactor(full,maximum: maxPixelDimension)
        return CGSize(width: ceil(full.width*factor), height: ceil(full.height*factor))
    }

    /// Top-left coordinates, in exported pixels (including exportScale).
    static func sourceFrame(image: NSImage, style: EditorStyle, maxPixelDimension: CGFloat? = nil) -> CGRect {
        let style = sanitized(style)
        let size = pixelSize(image)
        let full = dimensions(image: image, style: style)
        let output = dimensions(image: image, style: style, maxPixelDimension: maxPixelDimension)
        let scale = style.exportScale * previewFactor(full,maximum: maxPixelDimension)
        // Fractional origins would resample a native screenshot when a ratio adds odd padding.
        return CGRect(x: floor((output.width - size.width * scale) / 2),
                      y: floor((output.height - size.height * scale) / 2),
                      width: size.width * scale, height: size.height * scale)
    }

    /// A preview cap changes only this bitmap's working resolution. Omit it for native-quality export.
    static func render(image: NSImage, style: EditorStyle, annotations: [Annotation], backgroundImage: NSImage? = nil, maxPixelDimension: CGFloat? = nil) -> NSImage? {
        let style = sanitized(style)
        guard let source = cgImage(image) else { return nil }
        let fullOutput = dimensions(image: image, style: style)
        let factor = previewFactor(fullOutput,maximum: maxPixelDimension)
        let output = dimensions(image: image, style: style,maxPixelDimension: maxPixelDimension)
        let scale = style.exportScale*factor
        guard output.width <= 20000, output.height <= 20000,
              output.width * output.height <= 100_000_000,
              let context = bitmap(width: Int(output.width), height: Int(output.height), space: source.colorSpace) else { return nil }
        let full = CGRect(origin: .zero, size: output)
        context.clear(full)
        var backgroundStyle = style; backgroundStyle.exportScale = scale
        drawBackground(backgroundStyle, custom: backgroundImage, in: full, context: context, preview: maxPixelDimension != nil)

        let topFrame = sourceFrame(image: image, style: style,maxPixelDimension: maxPixelDimension)
        let frame = CGRect(x: topFrame.minX, y: output.height - topFrame.maxY, width: topFrame.width, height: topFrame.height)
        let inset = max(0, style.inset) * scale
        let card = frame.insetBy(dx: -inset, dy: -inset)
        let corner = min(max(0, style.radius * scale), min(card.width, card.height) / 2)
        let cardPath = CGPath(roundedRect: card, cornerWidth: corner, cornerHeight: corner, transform: nil)
        if style.shadow > 0 {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -max(2, style.shadow * 0.25) * scale), blur: style.shadow * scale, color: NSColor.black.withAlphaComponent(0.32).cgColor)
            context.setFillColor(NSColor.white.cgColor)
            context.addPath(cardPath); context.fillPath()
            context.restoreGState()
        }
        context.saveGState()
        context.addPath(cardPath); context.clip()
        if inset > 0 { context.setFillColor(NSColor.white.cgColor); context.fill(card) }
        context.interpolationQuality = scale == 1 ? .none : .high
        context.draw(source, in: frame)
        // Edits are flattened into the exported bitmap, never stored as removable layers.
        context.saveGState(); context.clip(to: frame)
        // Opaque redaction stays opaque even when a later pixelation overlaps it.
        let annotations = annotations.compactMap(sanitized)
        let ordinary = annotations.filter { $0.kind != .redact && $0.kind != .magnifier }
        let redacts = annotations.filter { $0.kind == .redact }
        let safeAnnotations = ordinary + redacts
        for annotation in ordinary + annotations.filter({ $0.kind == .magnifier }) + redacts {
            draw(annotation, source: source, in: frame, scale: scale, context: context, safeAnnotations: safeAnnotations)
        }
        context.restoreGState()
        context.restoreGState()
        if !style.watermark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drawWatermark(style.watermark, output: output, scale: scale, context: context)
        }
        guard let result = context.makeImage() else { return nil }
        let density = nativeScale(image: image) * style.exportScale
        return bitmapImage(cgImage: result, logicalSize: CGSize(width: fullOutput.width/density, height: fullOutput.height/density))
    }

    private static func previewFactor(_ full: CGSize, maximum: CGFloat?) -> Double {
        guard let maximum, maximum.isFinite else { return 1 }
        return min(1, max(1,min(8192,maximum))/max(1,max(full.width,full.height)))
    }

    static func data(image: NSImage, format: String = "png", quality: Double = 0.9) -> Data? {
        guard let cg = cgImage(image) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        // PNG/TIFF store DPI as metadata without reducing the underlying pixel dimensions.
        rep.size = sourceMetrics(image: image).logicalSize
        switch format.lowercased() {
        case "jpg", "jpeg":
            // Flatten transparent pixels onto white for JPEG.
            guard let context = bitmap(width: cg.width, height: cg.height, space: cg.colorSpace) else { return nil }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            guard let flattened = context.makeImage() else { return nil }
            let jpeg = NSBitmapImageRep(cgImage: flattened)
            jpeg.size = rep.size
            return jpeg.representation(using: .jpeg, properties: [.compressionFactor: bounded(quality, fallback: 0.9, lower: 0.1, upper: 1)])
        case "tiff", "tif": return rep.representation(using: .tiff, properties: [:])
        default: return rep.representation(using: .png, properties: [:])
        }
    }

    static func recognize(image: NSImage) throws -> [RecognizedLine] {
        guard let cg = cgImage(image) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try performOCR(request, image: cg)
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let b = observation.boundingBox
            return RecognizedLine(text: candidate.string, rect: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
        }.sorted { a, b in abs(a.rect.minY - b.rect.minY) < 0.008 ? a.rect.minX < b.rect.minX : a.rect.minY < b.rect.minY }
    }

    static func sensitiveAnnotations(image: NSImage) throws -> [Annotation] {
        guard let cg = cgImage(image) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try performOCR(request, image: cg)
        // Deliberately conservative patterns. Review before sharing: OCR cannot guarantee detection.
        let patterns = [
            #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
            #"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b"#,
            #"\b(?:[0-9][ -]?){13,19}\b"#,
            #"\b(?:sk[-_]|pk[-_]|ghp_|github_pat_|AIza|AKIA)[A-Za-z0-9_\-]{12,}\b"#,
            #"\bBearer\s+[A-Za-z0-9._\-+/=]{12,}"#
        ]
        let regexes = try patterns.map { try NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        var results: [Annotation] = []
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first else { continue }
            let string = text.string
            for regex in regexes {
                for match in regex.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
                    guard let range = Range(match.range, in: string), let box = try? text.boundingBox(for: range) else { continue }
                    let b = box.boundingBox
                    let rect = CGRect(x: b.minX - 0.004, y: 1 - b.maxY - 0.004, width: b.width + 0.008, height: b.height + 0.008).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                    guard !rect.isNull else { continue }
                    if results.contains(where: { normalizedRect($0).intersection(rect).width > rect.width * 0.8 && normalizedRect($0).intersection(rect).height > rect.height * 0.8 }) { continue }
                    results.append(Annotation(kind: .redact, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), colorHex: "#20212A"))
                }
            }
        }
        return results
    }

    static func crop(image: NSImage, rect: CGRect, snapToPixel: Bool = false) -> NSImage? {
        guard [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy({ $0.isFinite }) else { return nil }
        guard let source = cgImage(image) else { return nil }
        let normalized = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !normalized.isNull, normalized.width > 0, normalized.height > 0 else { return nil }
        // CGImage.cropping uses pixel coordinates with origin at the image's top left.
        let left = normalized.minX * Double(source.width), right = normalized.maxX * Double(source.width)
        let top = normalized.minY * Double(source.height), bottom = normalized.maxY * Double(source.height)
        let pixels = snapToPixel
            ? CGRect(x: left.rounded(), y: top.rounded(), width: right.rounded()-left.rounded(), height: bottom.rounded()-top.rounded())
            : CGRect(x: left, y: top, width: right-left, height: bottom-top).integral
        guard let cropped = source.cropping(to: pixels) else { return nil }
        let density = nativeScale(image: image)
        return bitmapImage(cgImage: cropped, logicalSize: CGSize(width: Double(cropped.width)/density, height: Double(cropped.height)/density))
    }

    static func autoBalanced(image: NSImage) -> NSImage? {
        guard let source = cgImage(image), source.width > 16, source.height > 16 else { return image }
        // Scan a small copy, ignoring nearly uniform outer margins. Avoid allocating the original at Retina size.
        let scale = min(1.0, 600.0 / Double(max(source.width, source.height)))
        let width = max(1, Int(Double(source.width) * scale)), height = max(1, Int(Double(source.height) * scale))
        guard let context = bitmap(width: width, height: height) else { return image }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return image }
        let stride = context.bytesPerRow
        func color(_ x: Int, _ y: Int) -> (Int, Int, Int) { let i = y * stride + x * 4; return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])) }
        let corners = [color(0, 0), color(width - 1, 0), color(0, height - 1), color(width - 1, height - 1)]
        let background = (corners.map { $0.0 }.reduce(0,+) / 4, corners.map { $0.1 }.reduce(0,+) / 4, corners.map { $0.2 }.reduce(0,+) / 4)
        func distance(_ p: (Int, Int, Int)) -> Int { abs(p.0-background.0) + abs(p.1-background.1) + abs(p.2-background.2) }
        guard corners.allSatisfy({ distance($0) < 60 }) else { return image }
        var minX = width, minY = height, maxX = 0, maxY = 0
        for y in 0..<height { for x in 0..<width where distance(color(x,y)) > 65 {
            minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y)
        } }
        guard minX < maxX, minY < maxY else { return image }
        // Keep a small breathing margin and avoid aggressive crops of photos/gradients.
        let margin = max(4, Int(Double(min(width, height)) * 0.025))
        minX = max(0,minX-margin); minY = max(0,minY-margin); maxX = min(width-1,maxX+margin); maxY = min(height-1,maxY+margin)
        let rectangle = CGRect(x: Double(minX)/Double(width), y: Double(minY)/Double(height), width: Double(maxX-minX+1)/Double(width), height: Double(maxY-minY+1)/Double(height))
        guard rectangle.width < 0.96 || rectangle.height < 0.96, rectangle.width > 0.1, rectangle.height > 0.1 else { return image }
        return crop(image: image, rect: rectangle)
    }

    private static func bitmap(width: Int, height: Int, space: CGColorSpace? = nil) -> CGContext? {
        guard width > 0, height > 0, width <= 20000, height <= 20000, width * height <= 100_000_000 else { return nil }
        let rgbSpace = space?.model == .rgb ? space! : colorSpace
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: rgbSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    }

    private static func performOCR(_ request: VNRecognizeTextRequest, image: CGImage) throws {
        let image = downsampleForOCR(image)
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
        catch {
            // Some Macs cannot initialize a GPU-backed Vision session. Retry on CPU.
            request.usesCPUOnly = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        }
    }

    private static func downsampleForOCR(_ image: CGImage) -> CGImage {
        let scale = min(1, 4096.0 / Double(max(image.width, image.height)))
        guard scale < 1, let context = bitmap(width: max(1, Int(Double(image.width)*scale)), height: max(1, Int(Double(image.height)*scale))) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage() ?? image
    }

    private static func bounded(_ value: Double, fallback: Double, lower: Double, upper: Double) -> Double {
        value.isFinite ? min(upper, max(lower, value)) : fallback
    }

    static func sanitized(_ original: EditorStyle) -> EditorStyle {
        var style = original
        style.padding = bounded(style.padding, fallback: 64, lower: 0, upper: 4096)
        style.inset = bounded(style.inset, fallback: 0, lower: 0, upper: 2048)
        style.radius = bounded(style.radius, fallback: 16, lower: 0, upper: 4096)
        style.shadow = bounded(style.shadow, fallback: 28, lower: 0, upper: 1024)
        style.ratio = bounded(style.ratio, fallback: 0, lower: 0, upper: 20)
        style.exportScale = bounded(style.exportScale, fallback: 1, lower: 0.1, upper: 4)
        style.backgroundBlur = bounded(style.backgroundBlur, fallback: 0, lower: 0, upper: 100)
        style.backgroundBrightness = bounded(style.backgroundBrightness, fallback: 1, lower: 0, upper: 2)
        style.watermark = String(style.watermark.prefix(500))
        return style
    }

    private static func sanitized(_ original: Annotation) -> Annotation? {
        guard [original.start.x, original.start.y, original.end.x, original.end.y].allSatisfy({ $0.isFinite }) else { return nil }
        var annotation = original
        annotation.start = CGPoint(x: min(1,max(0,annotation.start.x)),y: min(1,max(0,annotation.start.y)))
        annotation.end = CGPoint(x: min(1,max(0,annotation.end.x)),y: min(1,max(0,annotation.end.y)))
        annotation.lineWidth = bounded(annotation.lineWidth,fallback: 5,lower: 0.5,upper: 1000)
        annotation.fontSize = bounded(annotation.fontSize,fallback: 28,lower: 8,upper: 512)
        annotation.magnification = bounded(annotation.magnification,fallback: 2,lower: 1,upper: 8)
        annotation.text = String(annotation.text.prefix(2000))
        return annotation
    }

    static func color(hex: String) -> NSColor {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return .systemPink }
        return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
    }

    private static func drawBackground(_ style: EditorStyle, custom: NSImage?, in rect: CGRect, context: CGContext, preview: Bool) {
        if style.background == "transparent" { return }
        if (style.background == "custom" || style.background.hasPrefix("image:")), let custom, let original = cgImage(custom) {
            let key = "\(ObjectIdentifier(custom)):\(original.width)x\(original.height):\(style.backgroundBlur):\(style.backgroundBrightness):\(style.exportScale):\(Int(rect.width))x\(Int(rect.height)):\(preview)" as NSString
            let cached = backgroundCache.object(forKey: key)
            let cg: CGImage
            if let cached, cached.source === custom { cg = cached.pixels }
            else {
                cg = processedBackground(original, style: style, output: rect.size, preview: preview) ?? original
                if cg !== original {
                    let cost = cg.bytesPerRow*cg.height
                    if cost <= 16_000_000 { backgroundCache.setObject(BackgroundCacheEntry(source:custom,pixels:cg),forKey:key,cost:cost) }
                }
            }
            let ratio = max(rect.width / Double(cg.width), rect.height / Double(cg.height))
            let size = CGSize(width: Double(cg.width) * ratio, height: Double(cg.height) * ratio)
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: (rect.width-size.width)/2, y: (rect.height-size.height)/2, width: size.width, height: size.height))
            return
        }
        if style.background == "solid" {
            context.setFillColor(color(hex: style.solidHex).cgColor); context.fill(rect); return
        }
        let palettes: [String: [String]] = [
            "aurora": ["#5355DA", "#8C6CE8", "#E5A5DA"],
            "dusk": ["#1C2346", "#514079", "#D19796"],
            "ocean": ["#087BA3", "#48B7CF", "#C2F0DF"],
            "rose": ["#CB587D", "#F29BAA", "#FFD8B5"],
            "mint": ["#317B71", "#89BAA6", "#E8ECC6"],
            "sunset": ["#D45863", "#F79D65", "#FFDC9A"]
        ]
        let colors = (palettes[style.background] ?? palettes["aurora"]!).map { color(hex: $0).cgColor }
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0,0.5,1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0,y: rect.height), end: CGPoint(x: rect.width,y: 0), options: [.drawsBeforeStartLocation,.drawsAfterEndLocation])
        }
    }

    /// Background processing has its own bitmap. The captured screenshot never enters this path.
    private static func processedBackground(_ source: CGImage, style: EditorStyle, output: CGSize, preview: Bool) -> CGImage? {
        guard style.backgroundBlur > 0 || style.backgroundBrightness != 1 else { return source }
        // Blur removes high-frequency backdrop detail, so cap that working buffer independently.
        // A brightness-only edit retains the backdrop's native dimensions.
        let maxDimension = preview ? min(1800, max(output.width,output.height)) : (style.backgroundBlur > 0 ? 4096.0 : Double(max(source.width, source.height)))
        let workingScale = min(1, maxDimension / Double(max(source.width, source.height)))
        let width = max(1, Int(Double(source.width) * workingScale))
        let height = max(1, Int(Double(source.height) * workingScale))
        guard let context = bitmap(width: width, height: height, space: source.colorSpace), let pointer = context.data else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0,y: 0,width: width,height: height))
        if style.backgroundBlur > 0 {
            let fit = max(output.width/Double(width), output.height/Double(height))
            let sigma = style.backgroundBlur * style.exportScale / max(fit, 0.001)
            guard gaussianBlur(context: context,sigma: sigma) else { return nil }
        }
        if style.backgroundBrightness != 1 {
            let bytes = pointer.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height { for x in 0..<width {
                let index = y*context.bytesPerRow+x*4
                let alpha = Double(bytes[index+3])
                for channel in 0..<3 { bytes[index+channel] = UInt8(min(alpha, max(0, (Double(bytes[index+channel])*style.backgroundBrightness).rounded()))) }
            } }
        }
        return context.makeImage()
    }

    /// A separable Gaussian convolution, entirely on the CPU with no GPU/Metal dependency.
    private static func gaussianBlur(context: CGContext, sigma requestedSigma: Double) -> Bool {
        guard let pointer = context.data else { return false }
        let sigma = bounded(requestedSigma,fallback: 8,lower: 0.5,upper: 64)
        let half = Int(ceil(3*sigma))
        var weights = (-half...half).map { x in Float(exp(-Double(x*x)/(2*sigma*sigma))) }
        let total = weights.reduce(0,+)
        weights = weights.map { $0/total }
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: context.bytesPerRow*context.height,alignment: 64)
        defer { scratch.deallocate() }
        var input = vImage_Buffer(data: pointer,height: vImagePixelCount(context.height),width: vImagePixelCount(context.width),rowBytes: context.bytesPerRow)
        var output = vImage_Buffer(data: scratch,height: vImagePixelCount(context.height),width: vImagePixelCount(context.width),rowBytes: context.bytesPerRow)
        let count = UInt32(weights.count)
        let flags = vImage_Flags(kvImageEdgeExtend)
        if #available(macOS 14, *) {
            let result = vImageSepConvolve_ARGB8888(&input,&output,nil,0,0,weights,count,weights,count,0,nil,flags)
            guard result == kvImageNoError else { return false }
            memcpy(pointer,scratch,context.bytesPerRow*context.height)
        } else {
            // macOS 13 has the integer convolution API. Two 1D passes use the same Gaussian.
            let kernel = weights.map { Int16(max(0,($0*16384).rounded())) }
            let divisor = kernel.reduce(Int32(0)) { $0+Int32($1) }
            guard divisor > 0,
                  vImageConvolve_ARGB8888(&input,&output,nil,0,0,kernel,1,count,divisor,nil,flags) == kvImageNoError,
                  vImageConvolve_ARGB8888(&output,&input,nil,0,0,kernel,count,1,divisor,nil,flags) == kvImageNoError else { return false }
        }
        return true
    }

    private static func blurredImage(_ image: CGImage, sigma: Double, previewScale: Double) -> CGImage? {
        let scale = min(1,max(0.001,previewScale))
        let width = max(1,Int(ceil(Double(image.width)*scale))), height = max(1,Int(ceil(Double(image.height)*scale)))
        guard let context = bitmap(width: width,height: height,space: image.colorSpace) else { return nil }
        context.interpolationQuality = .high
        context.draw(image,in: CGRect(x:0,y:0,width:width,height:height))
        guard gaussianBlur(context:context,sigma:sigma*scale) else { return nil }
        return context.makeImage()
    }

    private static func normalizedRect(_ annotation: Annotation) -> CGRect {
        CGRect(x: min(annotation.start.x,annotation.end.x), y: min(annotation.start.y,annotation.end.y), width: abs(annotation.end.x-annotation.start.x), height: abs(annotation.end.y-annotation.start.y))
    }

    static func arrowGeometry(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat, minimumHeadLength: CGFloat = 10) -> ArrowGeometry? {
        guard [start.x,start.y,end.x,end.y,lineWidth,minimumHeadLength].allSatisfy({ $0.isFinite }) else { return nil }
        let length = hypot(end.x-start.x,end.y-start.y)
        guard length > 0.001 else { return nil }
        let dx = (end.x-start.x)/length, dy = (end.y-start.y)/length
        // A thick setting must still produce a clean arrow when the drag is short.
        let width = min(max(0.25,lineWidth),length*0.22)
        let headLength = min(length*0.46,max(max(0,minimumHeadLength),width*2.8))
        let halfHead = max(width*1.12,headLength*0.38)
        let base = CGPoint(x:end.x-dx*headLength,y:end.y-dy*headLength)
        let vertices = [end,CGPoint(x:base.x-dy*halfHead,y:base.y+dx*halfHead),CGPoint(x:base.x+dy*halfHead,y:base.y-dx*halfHead)]
        let radius = min(width*0.2,headLength*0.08)
        let head = CGMutablePath()
        for index in vertices.indices {
            let vertex = vertices[index], previous = vertices[(index+2)%3], next = vertices[(index+1)%3]
            let previousLength = hypot(previous.x-vertex.x,previous.y-vertex.y), nextLength = hypot(next.x-vertex.x,next.y-vertex.y)
            let a = min(radius,previousLength*0.2), b = min(radius,nextLength*0.2)
            let entry = CGPoint(x:vertex.x+(previous.x-vertex.x)/previousLength*a,y:vertex.y+(previous.y-vertex.y)/previousLength*a)
            let exit = CGPoint(x:vertex.x+(next.x-vertex.x)/nextLength*b,y:vertex.y+(next.y-vertex.y)/nextLength*b)
            if index == 0 { head.move(to:entry) } else { head.addLine(to:entry) }
            head.addQuadCurve(to:exit,control:vertex)
        }
        head.closeSubpath()
        return ArrowGeometry(start:start,shaftEnd:CGPoint(x:base.x+dx*headLength*0.22,y:base.y+dy*headLength*0.22),width:width,headLength:headLength,head:head)
    }

    static func drawArrow(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat, minimumHeadLength: CGFloat = 10, color: CGColor, context: CGContext) {
        guard let geometry = arrowGeometry(from:start,to:end,lineWidth:lineWidth,minimumHeadLength:minimumHeadLength) else { return }
        context.saveGState()
        context.setStrokeColor(color); context.setFillColor(color)
        context.setLineWidth(geometry.width); context.setLineCap(.round); context.setLineJoin(.round)
        context.move(to:geometry.start); context.addLine(to:geometry.shaftEnd); context.strokePath()
        context.addPath(geometry.head); context.fillPath()
        context.restoreGState()
    }

    /// Normalized top-left bounds of a true circle in source pixel space.
    static func magnifierBounds(_ annotation: Annotation, pixels: CGSize) -> CGRect {
        guard pixels.width > 0, pixels.height > 0,
              [pixels.width,pixels.height,annotation.start.x,annotation.start.y,annotation.end.x,annotation.end.y].allSatisfy({ $0.isFinite }) else { return .zero }
        let rect = normalizedRect(annotation)
        let diameter = min(rect.width*pixels.width,rect.height*pixels.height)
        return CGRect(x: rect.midX-diameter/pixels.width/2,y: rect.midY-diameter/pixels.height/2,width: diameter/pixels.width,height: diameter/pixels.height)
    }

    private static func drawMagnifier(_ annotation: Annotation, source: CGImage, in frame: CGRect, scale: Double, context: CGContext, safeAnnotations: [Annotation]) {
        let pixels = CGSize(width:source.width,height:source.height)
        let bounds = magnifierBounds(annotation,pixels:pixels)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let lens = CGRect(x:frame.minX+bounds.minX*frame.width,y:frame.maxY-bounds.maxY*frame.height,width:bounds.width*frame.width,height:bounds.height*frame.height)
        let zoom = bounded(annotation.magnification,fallback:2,lower:1,upper:8)
        let sampleWidth = bounds.width*pixels.width/zoom
        let sampleHeight = bounds.height*pixels.height/zoom
        let sample = CGRect(x:bounds.midX*pixels.width-sampleWidth/2,y:bounds.midY*pixels.height-sampleHeight/2,width:sampleWidth,height:sampleHeight)
        let safe = magnifierSample(source:source,rect:sample,scale:min(1,scale),annotations:safeAnnotations)
        context.saveGState()
        context.setShadow(offset:CGSize(width:0,height:-2*scale),blur:6*scale,color:NSColor.black.withAlphaComponent(0.28).cgColor)
        context.setFillColor(NSColor.white.cgColor); context.fillEllipse(in:lens)
        context.restoreGState()
        context.saveGState(); context.addEllipse(in:lens); context.clip()
        if let safe { context.interpolationQuality = .high; context.draw(safe,in:lens) }
        else { context.setFillColor(NSColor.black.cgColor); context.fill(lens) }
        context.restoreGState()
        let border = min(max(0.25,annotation.lineWidth*scale),min(lens.width,lens.height)/3)
        context.setLineWidth(border); context.setStrokeColor(color(hex:annotation.colorHex).cgColor)
        context.strokeEllipse(in:lens.insetBy(dx:border/2,dy:border/2))
    }

    /// Only the source patch below the lens is materialized. All lenses are excluded,
    /// and opaque masks are drawn last before any magnified pixels are produced.
    private static func magnifierSample(source: CGImage, rect: CGRect, scale: Double, annotations: [Annotation]) -> CGImage? {
        let scale = min(1,max(0.001,scale))
        let width = max(1,Int(ceil(rect.width*scale))), height = max(1,Int(ceil(rect.height*scale)))
        guard let context = bitmap(width:width,height:height,space:source.colorSpace) else { return nil }
        let frame = CGRect(x:-rect.minX*scale,y:(rect.maxY-Double(source.height))*scale,width:Double(source.width)*scale,height:Double(source.height)*scale)
        context.interpolationQuality = scale == 1 ? .none : .high
        context.draw(source,in:frame)
        let ordinary = annotations.filter { $0.kind != .magnifier && $0.kind != .redact }
        let masks = annotations.filter { $0.kind == .redact }
        for annotation in ordinary + masks {
            if annotation.kind == .blur {
                drawSampleBlur(annotation,source:source,sample:rect,frame:frame,scale:scale,context:context)
            } else { draw(annotation,source:source,in:frame,scale:scale,context:context) }
        }
        return context.makeImage()
    }

    private static func drawSampleBlur(_ annotation: Annotation, source: CGImage, sample: CGRect, frame: CGRect, scale: Double, context: CGContext) {
        let normalized = normalizedRect(annotation)
        let mask = CGRect(x:normalized.minX*Double(source.width),y:normalized.minY*Double(source.height),width:normalized.width*Double(source.width),height:normalized.height*Double(source.height))
        let overlap = sample.intersection(mask)
        guard !overlap.isNull, !overlap.isEmpty else { return }
        let sigma = bounded(max(4,annotation.lineWidth*2),fallback:8,lower:0.5,upper:64)
        let processing = overlap.insetBy(dx:-ceil(3*sigma),dy:-ceil(3*sigma)).intersection(mask).intersection(CGRect(x:0,y:0,width:source.width,height:source.height)).integral
        let clip = CGRect(x:frame.minX+mask.minX*scale,y:frame.maxY-mask.maxY*scale,width:mask.width*scale,height:mask.height*scale)
        context.saveGState(); context.clip(to:clip)
        if let crop = source.cropping(to:processing), let blurred = blurredImage(crop,sigma:sigma,previewScale:scale) {
            let destination = CGRect(x:frame.minX+processing.minX*scale,y:frame.maxY-processing.maxY*scale,width:processing.width*scale,height:processing.height*scale)
            context.interpolationQuality = .high; context.draw(blurred,in:destination)
        } else { context.setFillColor(NSColor.black.cgColor); context.fill(clip.integral) }
        context.restoreGState()
    }

    private static func draw(_ annotation: Annotation, source: CGImage, in frame: CGRect, scale: Double, context: CGContext, safeAnnotations: [Annotation] = []) {
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: frame.minX+p.x*frame.width, y: frame.maxY-p.y*frame.height) }
        let a = point(annotation.start), b = point(annotation.end)
        let rect = CGRect(x: min(a.x,b.x),y: min(a.y,b.y),width: abs(a.x-b.x),height: abs(a.y-b.y))
        let color = color(hex: annotation.colorHex)
        let width = max(0.25, annotation.lineWidth * scale)
        context.saveGState()
        context.setStrokeColor(color.cgColor); context.setFillColor(color.cgColor)
        context.setLineWidth(width); context.setLineCap(.round); context.setLineJoin(.round)
        switch annotation.kind {
        case .arrow:
            drawArrow(from:a,to:b,lineWidth:width,minimumHeadLength:10*scale,color:color.cgColor,context:context)
        case .rectangle: context.stroke(rect.insetBy(dx: min(width/2,rect.width/2),dy: min(width/2,rect.height/2)))
        case .ellipse: context.strokeEllipse(in: rect.insetBy(dx: min(width/2,rect.width/2),dy: min(width/2,rect.height/2)))
        case .redact: context.fill(rect.integral)
        case .magnifier:
            drawMagnifier(annotation,source:source,in:frame,scale:scale,context:context,safeAnnotations:safeAnnotations)
        case .pixelate, .blur:
            let normalized = normalizedRect(annotation).intersection(CGRect(x: 0,y: 0,width: 1,height: 1))
            let pixels = CGRect(x: normalized.minX*Double(source.width), y: normalized.minY*Double(source.height), width: normalized.width*Double(source.width), height: normalized.height*Double(source.height)).integral
            var masked = false
            if let cropped = source.cropping(to: pixels) {
                if annotation.kind == .blur, let blurred = blurredImage(cropped,sigma:max(4,annotation.lineWidth*2),previewScale: scale) {
                    context.interpolationQuality = .high; context.draw(blurred,in:rect); masked = true
                } else if annotation.kind == .pixelate, let small = bitmap(width: max(1,Int(rect.width/(13*scale))),height: max(1,Int(rect.height/(13*scale))),space: source.colorSpace) {
                    small.interpolationQuality = .low
                    small.draw(cropped,in: CGRect(x: 0,y: 0,width: small.width,height: small.height))
                    if let mosaic = small.makeImage() { context.interpolationQuality = .none; context.draw(mosaic,in: rect); masked = true }
                }
            }
            if !masked {
                // A failed masking filter must not silently export the unmodified private pixels.
                context.setFillColor(NSColor.black.cgColor); context.fill(rect.integral)
            }
        case .text:
            let font = NSFont.systemFont(ofSize: max(0.5,annotation.fontSize*scale),weight: .semibold)
            let string = NSAttributedString(string: annotation.text, attributes: [.font: font,.foregroundColor: color])
            let size = string.size()
            let origin = CGPoint(x: a.x,y: a.y-size.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context,flipped: false)
            string.draw(at: origin)
            NSGraphicsContext.restoreGraphicsState()
        }
        context.restoreGState()
    }

    private static func drawWatermark(_ text: String, output: CGSize, scale: Double, context: CGContext) {
        let font = NSFont.systemFont(ofSize: max(12*scale, min(output.width,output.height)*0.025),weight: .medium)
        let string = NSAttributedString(string: text,attributes: [.font:font,.foregroundColor:NSColor.white.withAlphaComponent(0.9)])
        let size = string.size()
        let box = CGRect(x: max(8,output.width-size.width-30*scale),y: 16*scale,width: size.width+20*scale,height: size.height+12*scale)
        context.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        context.addPath(CGPath(roundedRect: box,cornerWidth: 7*scale,cornerHeight: 7*scale,transform: nil)); context.fillPath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
        string.draw(at: CGPoint(x:box.minX+10*scale,y:box.minY+6*scale))
        NSGraphicsContext.restoreGraphicsState()
    }
}
