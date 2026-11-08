import AppKit

@main
struct ImageEngineTests {
    static func main() throws {
        let context = CGContext(data: nil, width: 400, height: 240, bitsPerComponent: 8, bytesPerRow: 1600, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 240))
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: 0, y: 120, width: 400, height: 120))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 120))
        let source = NSImage(cgImage: context.makeImage()!, size: CGSize(width: 200,height: 120))

        var style = EditorStyle()
        style.padding = 20
        style.inset = 0
        style.radius = 0
        style.shadow = 0
        style.background = "transparent"
        let annotation = Annotation(kind: .redact, start: CGPoint(x: 0.1,y: 0.1),end: CGPoint(x: 0.4,y: 0.4),colorHex: "#000000")
        let rendered = ImageEngine.render(image: source,style: style,annotations: [annotation])!
        let bitmap = NSBitmapImageRep(cgImage: ImageEngine.cgImage(rendered)!)
        assert(bitmap.pixelsWide == 440 && bitmap.pixelsHigh == 280,"Retina source pixels must be retained")
        let redacted = bitmap.colorAt(x: 100,y: 80)!.usingColorSpace(.deviceRGB)!
        let untouched = bitmap.colorAt(x: 100,y: 200)!.usingColorSpace(.deviceRGB)!
        assert(redacted.redComponent < 0.01 && redacted.greenComponent < 0.01 && redacted.blueComponent < 0.01,"Redaction must cover top-left source region")
        assert(untouched.blueComponent > 0.5,"Redaction must not flip vertically")

        let crop = ImageEngine.crop(image: source,rect: CGRect(x: 0,y: 0,width: 1,height: 0.5))!
        let cropBitmap = NSBitmapImageRep(cgImage: ImageEngine.cgImage(crop)!)
        assert(cropBitmap.pixelsWide == 400 && cropBitmap.pixelsHigh == 120)
        let cropColor = cropBitmap.colorAt(x: 10,y: 10)!.usingColorSpace(.deviceRGB)!
        assert(cropColor.redComponent > 0.5,"Crop origin must be top-left")
        assert(ImageEngine.data(image: rendered,format: "jpeg") != nil)
        let encoded = try JSONEncoder().encode([annotation])
        let decoded = try JSONDecoder().decode([Annotation].self,from: encoded)
        assert(decoded == [annotation])
        style.ratio = 1
        style.exportScale = 2
        let square = ImageEngine.dimensions(image: source,style: style)
        assert(square.width == 880 && square.height == 880)
        style.ratio = 0; style.exportScale = 1
        let pixelation = Annotation(kind: .pixelate,start: .zero,end: CGPoint(x: 1,y: 1))
        let safeRender = ImageEngine.render(image: source,style: style,annotations: [annotation,pixelation])!
        let safeBitmap = NSBitmapImageRep(cgImage: ImageEngine.cgImage(safeRender)!)
        assert(safeBitmap.colorAt(x: 100,y: 80)!.usingColorSpace(.deviceRGB)!.redComponent < 0.01,"Overlapping pixelation must never restore opaque redaction")

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x:0,y:0,width:400,height:240))
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x:80,y:60,width:240,height:120))
        let centered = NSImage(cgImage:context.makeImage()!,size:CGSize(width:400,height:240))
        let balanced = ImageEngine.autoBalanced(image:centered)!
        assert(ImageEngine.pixelSize(balanced).width < 300,"Auto-balance should trim uniform margins")

        let textContext = CGContext(data:nil,width:1000,height:300,bitsPerComponent:8,bytesPerRow:4000,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        textContext.setFillColor(NSColor.white.cgColor)
        textContext.fill(CGRect(x:0,y:0,width:1000,height:300))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext:textContext,flipped:false)
        NSAttributedString(string:"Email: alex@example.com",attributes:[.font:NSFont.systemFont(ofSize:40),.foregroundColor:NSColor.black]).draw(at:CGPoint(x:50,y:210))
        NSAttributedString(string:"Address: 192.168.1.24",attributes:[.font:NSFont.systemFont(ofSize:40),.foregroundColor:NSColor.black]).draw(at:CGPoint(x:50,y:120))
        NSGraphicsContext.restoreGraphicsState()
        let textImage = NSImage(cgImage:textContext.makeImage()!,size:CGSize(width:1000,height:300))
        do {
            let lines = try ImageEngine.recognize(image:textImage)
            assert(lines.contains(where:{$0.text.contains("alex@example.com")}),"OCR should recognize fixture email")
            let sensitive = try ImageEngine.sensitiveAnnotations(image:textImage)
            assert(sensitive.count >= 2,"Email and IP should receive separate redactions")
            assert(sensitive.contains(where:{$0.start.y < 0.4}),"Sensitive boxes must use top-left coordinates")
            print("PASS: Vision text recognition and sensitive-email/IP redaction coordinates")
        } catch {
            print("SKIP: Vision runtime unavailable in this environment: \(error)")
        }
        var invalid = EditorStyle()
        invalid.padding = .nan; invalid.inset = -.infinity; invalid.radius = -50
        invalid.shadow = .infinity; invalid.ratio = .nan; invalid.exportScale = .nan
        assert(ImageEngine.render(image:source,style:invalid,annotations:[]) != nil,"Non-finite style inputs must be sanitized")
        invalid.padding = 1e100; invalid.inset = 1e100; invalid.exportScale = 1e100
        assert(ImageEngine.render(image:source,style:invalid,annotations:[]) == nil,"Oversized output must be rejected before allocation")
        assert(ImageEngine.crop(image:source,rect:CGRect(x:Double.nan,y:0,width:1,height:1)) == nil)
        print("PASS: Retina size, opaque redaction position, overlapping pixelation, crop orientation, JPEG, model round-trip, aspect ratio, export scale, auto-balance and numeric bounds")
        try checkRetinaFidelity()
        try checkImageBackgrounds()
        try checkBlurAnnotations()
        checkRetinaAfterDrawing()
        try checkMagnifier()
        checkArrowGeometry()
    }

    static func rgba(_ image: NSImage) -> (bytes: [UInt8], width: Int, height: Int) {
        let source = ImageEngine.cgImage(image)!
        let context = CGContext(data:nil,width:source.width,height:source.height,bitsPerComponent:8,bytesPerRow:source.width*4,space:source.colorSpace!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.interpolationQuality = .none
        context.draw(source,in:CGRect(x:0,y:0,width:source.width,height:source.height))
        return (Array(UnsafeBufferPointer(start:context.data!.assumingMemoryBound(to:UInt8.self),count:source.width*source.height*4)),source.width,source.height)
    }

    static func checkRetinaFidelity() throws {
        let width = 80, height = 45
        var pixels = [UInt8](repeating:255,count:width*height*4)
        for y in 0..<height { for x in 0..<width {
            let i = (y*width+x)*4
            pixels[i] = (x+y)%2 == 0 ? 255 : 0
            pixels[i+1] = UInt8((x*31)%256); pixels[i+2] = UInt8((y*47)%256)
        } }
        let provider = CGDataProvider(data:Data(pixels) as CFData)!
        let cg = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let retina = NSImage(cgImage:cg,size:CGSize(width:40,height:22.5))
        let metrics = ImageEngine.sourceMetrics(image:retina)
        assert(metrics.nativeScale == 2 && metrics.pixelSize.width == 80 && metrics.logicalSize.width == 40)
        var style = EditorStyle()
        style.padding = 0; style.radius = 0; style.shadow = 0; style.background = "transparent"; style.ratio = 1
        let native = ImageEngine.render(image:retina,style:style,annotations:[])!
        let preview = ImageEngine.render(image:retina,style:style,annotations:[],maxPixelDimension:32)!
        assert(ImageEngine.pixelSize(preview) == CGSize(width:32,height:32),"Editing preview must stay within its pixel budget")
        assert(preview.size == native.size,"A bounded preview must keep the full composition's logical size")
        let frame = ImageEngine.sourceFrame(image:retina,style:style)
        assert(frame.minY == floor(frame.minY),"Native source must be pixel aligned even with odd ratio padding")
        let result = rgba(native)
        for y in 0..<height { for x in 0..<width { for channel in 0..<4 {
            assert(result.bytes[((Int(frame.minY)+y)*result.width+Int(frame.minX)+x)*4+channel] == pixels[(y*width+x)*4+channel],"Native export must retain every original source pixel without interpolation")
        } } }
        let afterPreview = ImageEngine.render(image:retina,style:style,annotations:[])!
        assert(rgba(afterPreview).bytes == result.bytes,"Preview downsampling must never mutate the source or full-quality export")
        let previewFrame = ImageEngine.sourceFrame(image:retina,style:style,maxPixelDimension:32)
        assert(previewFrame.minX >= 0 && previewFrame.maxX <= 32 && previewFrame.minY >= 0 && previewFrame.maxY <= 32)
        let encoded = ImageEngine.data(image:native,format:"png",quality:0.1)!
        assert(encoded == ImageEngine.data(image:native,format:"png",quality:1),"PNG must ignore lossy JPEG quality settings")
        let reloaded = NSImage(data:encoded)!
        assert(rgba(reloaded).bytes == result.bytes,"PNG round-trip must retain exact raster pixels")
        assert(abs(ImageEngine.nativeScale(image:reloaded)-2) < 0.002,"PNG round-trip must retain 144dpi Retina metadata")
        let cropped = ImageEngine.crop(image:retina,rect:CGRect(x:0,y:0,width:0.5,height:1))!
        assert(ImageEngine.pixelSize(cropped).width == 40 && ImageEngine.nativeScale(image:cropped) == 2,"Crop must retain native Retina density")
        style.exportScale = 2
        let enlarged = ImageEngine.render(image:retina,style:style,annotations:[])!
        assert(ImageEngine.pixelSize(enlarged).width == 160 && enlarged.size == native.size,"Larger export must double pixels while retaining the same logical size")
        assert(ImageEngine.nativeScale(image:enlarged) == 4,"2x larger is 4x logical density for an already-2x source")
        let p3Space = CGColorSpace(name:CGColorSpace.displayP3)!
        let p3CG = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:p3Space,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        var plain = EditorStyle(); plain.padding = 0; plain.radius = 0; plain.shadow = 0; plain.background = "transparent"
        let p3Image = NSImage(cgImage:p3CG,size:CGSize(width:40,height:22.5))
        let p3Rendered = ImageEngine.render(image:p3Image,style:plain,annotations:[])!
        assert(rgba(p3Rendered).bytes == pixels,"Native export must preserve Display P3 pixel values")
        assert((ImageEngine.cgImage(p3Rendered)!.colorSpace!.name! as String) == (p3Space.name! as String),"Render must retain source color space")
        print("PASS: Native Retina source metrics, exact pixel-grid fidelity with odd padding, lossless PNG round-trip, DPI metadata, crop density and honest 2x enlargement")
    }

    static func checkImageBackgrounds() throws {
        let legacy = try JSONDecoder().decode(EditorStyle.self,from:Data(#"{"padding":20,"background":"image:test"}"#.utf8))
        assert(legacy.backgroundBlur == 0 && legacy.backgroundBrightness == 1 && legacy.exportScale == 1,"Old presets must decode with new feature defaults")
        let bgContext = CGContext(data:nil,width:100,height:100,bitsPerComponent:8,bytesPerRow:400,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        bgContext.setFillColor(NSColor.white.cgColor); bgContext.fill(CGRect(x:0,y:0,width:100,height:100))
        bgContext.setFillColor(NSColor.black.cgColor); bgContext.fill(CGRect(x:50,y:0,width:50,height:100))
        let backdrop = NSImage(cgImage:bgContext.makeImage()!,size:CGSize(width:100,height:100))
        let smallCG = bgContext.makeImage()!.cropping(to:CGRect(x:0,y:0,width:20,height:20))!
        let source = NSImage(cgImage:smallCG,size:CGSize(width:20,height:20))
        var style = EditorStyle(); style.padding = 40; style.radius = 0; style.shadow = 0; style.background = "image:test"
        let plain = ImageEngine.render(image:source,style:style,annotations:[],backgroundImage:backdrop)!
        let plainPixels = rgba(plain)
        assert(plainPixels.bytes[(5*100+10)*4] == 255 && plainPixels.bytes[(5*100+90)*4] == 0)
        style.backgroundBlur = 8
        let blurred = rgba(ImageEngine.render(image:source,style:style,annotations:[],backgroundImage:backdrop)!)
        let softenedEdge = blurred.bytes[(5*100+49)*4]
        assert(softenedEdge > 30 && softenedEdge < 245,"Blur must soften image-backdrop edges")
        // The screenshot's own pixel stays exact while the backdrop is filtered.
        assert(blurred.bytes[(50*100+50)*4] == 255)
        style.backgroundBlur = 100
        let maximumBlur = rgba(ImageEngine.render(image:source,style:style,annotations:[],backgroundImage:backdrop)!)
        assert(maximumBlur.bytes[(5*100+49)*4] > 30 && maximumBlur.bytes[(5*100+49)*4] < 245,"Maximum blur must handle kernels larger than the image")
        style.backgroundBlur = 0; style.backgroundBrightness = 0.5
        let dimmed = rgba(ImageEngine.render(image:source,style:style,annotations:[],backgroundImage:backdrop)!)
        assert(abs(Int(dimmed.bytes[(5*100+10)*4])-128) <= 1 && dimmed.bytes[(50*100+50)*4] == 255,"Brightness must affect only backdrop pixels")
        let encoded = try JSONEncoder().encode(style)
        assert(tryDecodeStyle(encoded) == style)
        print("PASS: Backward-compatible presets, image-library background keys, CPU blur, brightness and untouched screenshot pixels")
    }

    static func tryDecodeStyle(_ data:Data) -> EditorStyle? { try? JSONDecoder().decode(EditorStyle.self,from:data) }

    static func checkBlurAnnotations() throws {
        let width = 80, height = 40
        var pixels = [UInt8](repeating:255,count:width*height*4)
        for y in 0..<height { for x in 0..<width {
            let v:UInt8 = x%2 == 0 ? 0 : 255
            for channel in 0..<3 { pixels[(y*width+x)*4+channel] = v }
        } }
        let cg = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),provider:CGDataProvider(data:Data(pixels) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let image = NSImage(cgImage:cg,size:CGSize(width:40,height:20))
        var style = EditorStyle(); style.padding = 0; style.radius = 0; style.shadow = 0; style.background = "transparent"
        let blur = Annotation(kind:.blur,start:CGPoint(x:0.25,y:0.25),end:CGPoint(x:0.75,y:0.75),lineWidth:4)
        let filtered = rgba(ImageEngine.render(image:image,style:style,annotations:[blur])!)
        let inside = Int(filtered.bytes[(20*width+40)*4])
        let adjacent = Int(filtered.bytes[(20*width+41)*4])
        assert(inside > 70 && inside < 185 && abs(inside-adjacent) < 5,"Gaussian blur must reduce high-frequency source transitions, not paint a solid fallback")
        for y in [0,5,35,39] { for x in 0..<width { for c in 0..<4 {
            assert(filtered.bytes[(y*width+x)*4+c] == pixels[(y*width+x)*4+c],"Blur must leave pixels outside its rectangle untouched")
        } } }
        let opaque = Annotation(kind:.redact,start:CGPoint(x:0.45,y:0.4),end:CGPoint(x:0.55,y:0.6),colorHex:"#000000")
        let safe = rgba(ImageEngine.render(image:image,style:style,annotations:[opaque,blur])!)
        assert(safe.bytes[(20*width+40)*4] == 0 && safe.bytes[(20*width+40)*4+3] == 255,"Later Gaussian blur must never uncover opaque redaction")
        let encoded = try JSONEncoder().encode(blur)
        let decoded = try JSONDecoder().decode(Annotation.self,from:encoded)
        assert(decoded == blur)
        print("PASS: Gaussian region blur reduces high-frequency transitions, leaves outside pixels unchanged and preserves opaque redaction")
    }

    static func checkRetinaAfterDrawing() {
        let context = CGContext(data:nil,width:600,height:400,bitsPerComponent:8,bytesPerRow:2400,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemBlue.cgColor); context.fill(CGRect(x:0,y:0,width:600,height:400))
        let imported = NSImage(cgImage:context.makeImage()!,size:CGSize(width:300,height:200))
        let stable = ImageEngine.materializedImage(imported)!
        assert(stable.representations.contains(where:{($0 as? NSBitmapImageRep)?.pixelsWide == 600}),"Imported snapshots must materialize their original native bitmap")
        var style = EditorStyle(); style.padding = 0; style.radius = 0; style.shadow = 0; style.background = "transparent"
        let rendered = ImageEngine.render(image:stable,style:style,annotations:[])!
        assert(rendered.representations.contains(where:{($0 as? NSBitmapImageRep)?.pixelsWide == 600}),"Rendered results must retain an explicit native bitmap representation")
        for backingScale in [1,2] {
            let target = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:300*backingScale,pixelsHigh:200*backingScale,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:1200*backingScale,bitsPerPixel:32)!
            target.size = CGSize(width:300,height:200)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:target)
            for image in [stable,rendered] {
                image.draw(in:CGRect(x:0,y:0,width:300,height:200),from:.zero,operation:.sourceOver,fraction:1)
                let cropped = ImageEngine.crop(image:image,rect:CGRect(x:0.25,y:0.25,width:0.5,height:0.5))!
                assert(ImageEngine.pixelSize(image) == CGSize(width:600,height:400),"Drawing at a lower backing scale cannot shrink the stored source")
                assert(ImageEngine.pixelSize(cropped) == CGSize(width:300,height:200),"Draw-then-crop must select half of native Retina pixels, not logical points")
                assert(ImageEngine.nativeScale(image:cropped) == 2)
                assert(cropped.representations.contains(where:{($0 as? NSBitmapImageRep)?.pixelsWide == 300}))
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        print("PASS: Bitmap-backed Retina images preserve600×400 native pixels through1x/2x AppKit drawing and half-size cropping")
    }

    static func checkMagnifier() throws {
        let width = 200, height = 160
        let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x:0,y:0,width:width,height:height))
        context.setFillColor(NSColor(srgbRed:1,green:0,blue:0,alpha:1).cgColor)
        context.fill(CGRect(x:102,y:78,width:2,height:4))
        context.setFillColor(NSColor(srgbRed:0,green:0,blue:1,alpha:1).cgColor)
        context.fill(CGRect(x:80,y:96,width:4,height:4))
        let image = ImageEngine.bitmapImage(cgImage:context.makeImage()!,logicalSize:CGSize(width:100,height:80))
        var style = EditorStyle(); style.padding = 0; style.radius = 0; style.shadow = 0; style.background = "transparent"
        var lens = Annotation(kind:.magnifier,start:CGPoint(x:0.3,y:0.25),end:CGPoint(x:0.7,y:0.75),colorHex:"#246BF0",lineWidth:2,magnification:2)
        let bounds = ImageEngine.magnifierBounds(lens,pixels:CGSize(width:width,height:height))
        assert(abs(bounds.width*Double(width)-bounds.height*Double(height)) < 0.0001)
        func color(_ output:NSImage,_ x:Int,_ y:Int) -> (Int,Int,Int) {
            let bitmap = rgba(output); let index=(y*bitmap.width+x)*4
            return (Int(bitmap.bytes[index]),Int(bitmap.bytes[index+1]),Int(bitmap.bytes[index+2]))
        }
        let twice = ImageEngine.render(image:image,style:style,annotations:[lens])!
        let detail2 = color(twice,106,80)
        assert(detail2.0 > 200 && detail2.1 < 50 && detail2.2 < 50,"2x lens must enlarge the off-center source detail at the correct location")
        let corner = color(twice,63,43)
        assert(corner.0 > 245 && corner.1 > 245 && corner.2 > 245,"Magnified blue sample corner must be clipped outside the circular lens")
        lens.magnification = 1
        let unity = ImageEngine.render(image:image,style:style,annotations:[lens])!
        assert(color(unity,102,80).0 > 240 && color(unity,106,80).1 > 240,"1x magnification must preserve the original detail position")
        lens.magnification = -20
        assert(rgba(ImageEngine.render(image:image,style:style,annotations:[lens])!).bytes == rgba(unity).bytes,"Magnification must clamp at1x")
        lens.magnification = 4
        let four = ImageEngine.render(image:image,style:style,annotations:[lens])!
        let detail4 = color(four,112,80)
        assert(detail4.0 > 200 && detail4.1 < 50 && detail4.2 < 50,"4x lens must enlarge a smaller source patch")
        lens.magnification = 8
        let eight = ImageEngine.render(image:image,style:style,annotations:[lens])!
        let detail8 = color(eight,124,80)
        assert(detail8.0 > 200 && detail8.1 < 50 && detail8.2 < 50,"8x lens must retain native screenshot detail")
        lens.magnification = 99
        assert(rgba(ImageEngine.render(image:image,style:style,annotations:[lens])!).bytes == rgba(eight).bytes,"Magnification must clamp at8x")
        lens.magnification = .nan
        assert(rgba(ImageEngine.render(image:image,style:style,annotations:[lens])!).bytes == rgba(twice).bytes,"Non-finite magnification must fall back to2x")
        lens.magnification = 2
        let mask = Annotation(kind:.redact,start:CGPoint(x:102.0/200,y:78.0/160),end:CGPoint(x:104.0/200,y:82.0/160),colorHex:"#000000")
        let safe = ImageEngine.render(image:image,style:style,annotations:[lens,mask])!
        let hidden = color(safe,106,80)
        assert(hidden.0 < 5 && hidden.1 < 5 && hidden.2 < 5,"Lens must not expose redacted detail magnified beyond the original mask rectangle")
        let safePixels = rgba(safe)
        for y in 43..<117 { for x in 63..<137 {
            let i=(y*width+x)*4
            assert(!(safePixels.bytes[i]>180 && safePixels.bytes[i+1]<70 && safePixels.bytes[i+2]<70),"No original red private pixels may survive inside the magnifier")
        } }
        let edge = Annotation(kind:.magnifier,start:.zero,end:CGPoint(x:0.2,y:0.25),lineWidth:2,magnification:4)
        let edgeOutput = ImageEngine.render(image:image,style:style,annotations:[edge])!
        assert(ImageEngine.pixelSize(edgeOutput) == CGSize(width:width,height:height))
        assert(color(edgeOutput,0,0).0 > 240,"Lens at the image edge must preserve outside-circle pixels")
        let preview = ImageEngine.render(image:image,style:style,annotations:[lens,mask],maxPixelDimension:80)!
        assert(ImageEngine.pixelSize(preview) == CGSize(width:80,height:64) && preview.size == safe.size)
        let previewHidden = color(preview,42,32)
        assert(previewHidden.0 < 20 && previewHidden.1 < 20 && previewHidden.2 < 20,"Bounded preview must also magnify the flattened redaction")
        assert(ImageEngine.nativeScale(image:safe) == 2)
        style.exportScale = 2
        let retinaLarger = ImageEngine.render(image:image,style:style,annotations:[lens,mask])!
        assert(ImageEngine.pixelSize(retinaLarger) == CGSize(width:400,height:320) && ImageEngine.nativeScale(image:retinaLarger) == 4)
        assert(color(retinaLarger,212,160).0 < 10,"Larger Retina export must preserve masking inside the magnifier")
        var json = try JSONSerialization.jsonObject(with:JSONEncoder().encode(lens)) as! [String:Any]
        json.removeValue(forKey:"magnification")
        let legacy = try JSONDecoder().decode(Annotation.self,from:JSONSerialization.data(withJSONObject:json))
        assert(legacy.magnification == 2,"Old annotations without magnification must decode")
        json.removeValue(forKey:"id"); json.removeValue(forKey:"text"); json.removeValue(forKey:"fontSize"); json.removeValue(forKey:"lineWidth"); json.removeValue(forKey:"colorHex")
        let sparse = try JSONDecoder().decode(Annotation.self,from:JSONSerialization.data(withJSONObject:json))
        assert(sparse.magnification == 2 && sparse.lineWidth == 5 && sparse.fontSize == 28)
        var changed = lens; changed.magnification = 4
        assert(changed != lens && Set([changed,lens]).count == 2)
        let decoded = try JSONDecoder().decode(Annotation.self,from:JSONEncoder().encode(changed))
        assert(decoded == changed)
        // A lens must magnify the filtered pixels, rather than reconstruct raw stripe detail.
        let stripeContext = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        stripeContext.setFillColor(NSColor.white.cgColor);stripeContext.fill(CGRect(x:0,y:0,width:width,height:height))
        stripeContext.setFillColor(NSColor.black.cgColor)
        for x in stride(from:0,to:width,by:2) { stripeContext.fill(CGRect(x:x,y:0,width:1,height:height)) }
        let striped = ImageEngine.bitmapImage(cgImage:stripeContext.makeImage()!,logicalSize:CGSize(width:100,height:80))
        style.exportScale = 1
        for kind in [AnnotationKind.blur,.pixelate] {
            let filter = Annotation(kind:kind,start:.zero,end:CGPoint(x:1,y:1),lineWidth:4)
            let filtered = ImageEngine.render(image:striped,style:style,annotations:[lens,filter])!
            let flattened = ImageEngine.render(image:striped,style:style,annotations:[filter])!
            let reference = ImageEngine.render(image:flattened,style:style,annotations:[lens])!
            for y in 60..<100 { for x in 80..<120 {
                let actual = color(filtered,x,y), expected = color(reference,x,y)
                assert(abs(actual.0-expected.0)<3 && abs(actual.1-expected.1)<3 && abs(actual.2-expected.2)<3,"Magnifier must sample flattened\(kind.rawValue) pixels rather than raw hidden stripes")
            } }
        }
        // Overlapping lenses never enter another lens's source patch. In particular,
        // the smaller lens's colored border must not become enlarged in the top lens.
        let smallLens = Annotation(kind:.magnifier,start:CGPoint(x:0.375,y:0.4375),end:CGPoint(x:0.475,y:0.5625),colorHex:"#00CC00",lineWidth:6,magnification:4)
        let stacked = ImageEngine.render(image:image,style:style,annotations:[smallLens,lens])!
        let soloPixels = rgba(twice), stackedPixels = rgba(stacked)
        for y in 50..<110 { for x in 70..<130 where (x-100)*(x-100)+(y-80)*(y-80)<29*29 {
            let i=(y*width+x)*4
            assert(Array(soloPixels.bytes[i..<i+4]) == Array(stackedPixels.bytes[i..<i+4]),"Overlapping magnifiers must sample edits without recursively magnifying another lens")
        } }
        let invalidLens = Annotation(kind:.magnifier,start:CGPoint(x:Double.nan,y:0),end:CGPoint(x:1,y:1))
        assert(ImageEngine.magnifierBounds(invalidLens,pixels:CGSize(width:width,height:height)) == .zero)
        assert(rgba(ImageEngine.render(image:image,style:style,annotations:[invalidLens])!).bytes == rgba(ImageEngine.render(image:image,style:style,annotations:[])!).bytes,"Non-finite lens geometry must be skipped")
        if let path = ProcessInfo.processInfo.environment["SNAPDRIVE_MAGNIFIER_PREVIEW"] { try ImageEngine.data(image:twice)!.write(to:URL(fileURLWithPath:path)) }
        print("PASS: Magnifier1x/2x/4x/8x zoom/clamping, circular/edge clipping, redaction/blur/pixelation safety, nonrecursive overlapping lenses, native Retina export, capped preview and legacy annotation decoding")
    }

    static func checkArrowGeometry() {
        let space=CGColorSpace(name:CGColorSpace.sRGB)!
        func bitmap(_ width:Int,_ height:Int)->CGContext{CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!}
        let sourceContext=bitmap(400,240)
        sourceContext.setFillColor(NSColor.white.cgColor);sourceContext.fill(CGRect(x:0,y:0,width:400,height:240))
        let source=ImageEngine.bitmapImage(cgImage:sourceContext.makeImage()!,logicalSize:CGSize(width:200,height:120))
        let arrow=Annotation(kind:.arrow,start:CGPoint(x:0.15,y:0.6),end:CGPoint(x:0.85,y:0.25),colorHex:"#F04A67",lineWidth:20)
        var style=EditorStyle();style.padding=0;style.inset=0;style.radius=0;style.shadow=0;style.background="transparent"
        // The canvas and export use the same filled head/round shaft at native,
        // enlarged Retina, and Fit-preview scales, including stroke/head sizes.
        for scale in [0.5,1.0,2.0] {
            style.exportScale=scale
            let result=ImageEngine.render(image:source,style:style,annotations:[arrow])!
            let reference=bitmap(Int(400*scale),Int(240*scale))
            reference.setFillColor(NSColor.white.cgColor);reference.fill(CGRect(x:0,y:0,width:400*scale,height:240*scale))
            ImageEngine.drawArrow(from:CGPoint(x:60*scale,y:96*scale),to:CGPoint(x:340*scale,y:180*scale),lineWidth:20*scale,minimumHeadLength:10*scale,color:ImageEngine.color(hex:arrow.colorHex).cgColor,context:reference)
            let expected=ImageEngine.bitmapImage(cgImage:reference.makeImage()!)
            assert(rgba(result).bytes == rgba(expected).bytes,"Live arrow geometry must match exported stroke and head at Fit/Retina scale\(scale)")
            if scale == 1,let path=ProcessInfo.processInfo.environment["SNAPDRIVE_ARROW_PREVIEW"]{try? ImageEngine.data(image:result)?.write(to:URL(fileURLWithPath:path))}
        }
        for length in [5.0,10.0,30.0,120.0,400.0] { for width in [0.5,4.0,20.0,1000.0] {
            let shape=ImageEngine.arrowGeometry(from:CGPoint(x:20,y:50),to:CGPoint(x:20+length,y:50),lineWidth:width)!
            assert(shape.width <= length*0.22+0.0001 && shape.headLength <= length*0.46+0.0001,"Short arrows must bound thick shafts and arrowheads within their drag length")
            assert(shape.head.boundingBoxOfPath.maxX <= 20+length+0.001 && shape.head.boundingBoxOfPath.minX >= 20-0.001,"An arrowhead must never extend behind its starting point or past its tip")
        } }
        assert(ImageEngine.arrowGeometry(from:.zero,to:.zero,lineWidth:20) == nil)
        assert(ImageEngine.arrowGeometry(from:.zero,to:CGPoint(x:Double.nan,y:2),lineWidth:20) == nil)
        print("PASS: Shared filled/rounded arrow draft/export pixels at Fit/native/Retina scales, finite geometry and bounded short-arrow/thick-stroke proportions")
    }
}
