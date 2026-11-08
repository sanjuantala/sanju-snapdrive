import AppKit
import SwiftUI

@main struct IconChecks {
    @MainActor static func main() throws {
        var committed:[Double]=[]
        let control=ToolNumberField(value:4,range:0.5...1000,onCommit:{committed.append($0)})
        let coordinator=ToolNumberField.Coordinator(control)
        let field=NSTextField()
        for (input,expected) in [("37.5",37.5),("-10",0.5),("2000",1000.0)] {
            field.stringValue=input
            coordinator.controlTextDidEndEditing(Notification(name:NSControl.textDidEndEditingNotification,object:field))
            assert(committed.last==expected,"Custom native numeric input must commit and clamp: \(input)")
        }
        let count=committed.count
        field.stringValue="invalid"
        coordinator.controlTextDidEndEditing(Notification(name:NSControl.textDidEndEditingNotification,object:field))
        assert(committed.count==count && field.stringValue=="4","Invalid input restores the current value without changing the document")
        field.stringValue="99"
        _ = coordinator.control(field,textView:NSTextView(),doCommandBy:NSSelectorFromString("cancelOperation:"))
        assert(committed.count==count && field.stringValue=="4","Escape cancels numeric input")
        try checkMenuContrast(output: ProcessInfo.processInfo.environment["SNAPDRIVE_ICON_QA_OUTPUT"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("menu-contrast.png"))
        let names=ToolIconLibrary.names
        assert(names.count==23 && names.contains("magnifier") && names.contains("chevron") && names.contains("clear"))
        let rows=(names.count+4)/5, height=rows*150+20
        let context=CGContext(data:nil,width:1000,height:height,bitsPerComponent:8,bytesPerRow:4000,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:0.97,green:0.97,blue:0.99,alpha:1));context.fill(CGRect(x:0,y:0,width:1000,height:height))
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        for (i,name) in names.enumerated(){
            guard let url=ToolIconLibrary.assetURL(name),let loaded=NSImage(contentsOf:url) else{fatalError("Missing SVG \(name)")}
            assert(loaded.isValid && loaded.size==NSSize(width:24,height:24))
            assert(ToolIconLibrary.image(name) === ToolIconLibrary.image(name),"Image cache must be reused")
            var masks:[[UInt8]]=[]
            for image in [loaded,ToolIconLibrary.nativeImage(name)] {
                let pixelContext=CGContext(data:nil,width:96,height:96,bitsPerComponent:8,bytesPerRow:384,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:pixelContext,flipped:false)
                image.draw(in:CGRect(x:0,y:0,width:96,height:96),from:.zero,operation:.sourceOver,fraction:1)
                NSGraphicsContext.restoreGraphicsState()
                let bytes=pixelContext.data!.assumingMemoryBound(to:UInt8.self)
                let mask=(0..<(96*96)).map{bytes[$0*4+3]};masks.append(mask)
                let ink=mask.filter{$0>32}.count
                assert(ink>250 && ink<7000,"Glyph must contain crisp nonempty vector marks: \(name), \(ink)")
            }
            let mismatch=zip(masks[0],masks[1]).map{abs(Int($0)-Int($1))}.reduce(0,+)
            assert(Double(mismatch)/Double(96*96*255)<0.04,"Native fallback must follow authored SVG pixel footprint: \(name)")
            let x=CGFloat(i%5)*200,y=CGFloat(rows-1-i/5)*150
            loaded.draw(in:CGRect(x:x+48,y:y+55,width:48,height:48),from:.zero,operation:.sourceOver,fraction:1)
            ToolIconLibrary.nativeImage(name).draw(in:CGRect(x:x+112,y:y+55,width:48,height:48),from:.zero,operation:.sourceOver,fraction:1)
            name.draw(at:CGPoint(x:x+50,y:y+25),withAttributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        let data=NSBitmapImageRep(cgImage:context.makeImage()!).representation(using:.png,properties:[:])!
        try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
        print("PASS 23 Lucide SVG assets including magnifier, chevron and clear, 24-point grid, image cache, nonempty SVG/native renders, matching SVG/path pixel footprints and real dark popover-trigger enabled/disabled contrast; custom numeric commits/clamps, invalid input and Escape")
    }
    @MainActor static func checkMenuContrast(output: URL) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited); app.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: AnyView(MenuContrastFixture()))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 112), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua); window.contentView = host
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 112)
        let end = Date().addingTimeInterval(0.3)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        host.layoutSubtreeIfNeeded()
        // Match 1× and 2× physical icon pixels regardless of the window's inherited
        // display density. Use AppKit's own cache bitmap: hand-built bitmap reps can
        // omit SwiftUI layer contents and are not a valid snapshot of the trigger.
        guard let initial = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No menu fixture bitmap") }
        let backingScale = CGFloat(initial.pixelsWide) / host.bounds.width
        for scale in [1, 2] {
            let viewScale = CGFloat(scale) / backingScale
            let size = CGSize(width: 320 * viewScale, height: 112 * viewScale)
            host.rootView = AnyView(MenuContrastFixture().scaleEffect(viewScale, anchor: .topLeading).frame(width: size.width, height: size.height, alignment: .topLeading))
            window.setContentSize(size); host.frame = CGRect(origin: .zero, size: size)
            let renderEnd = Date().addingTimeInterval(0.12)
            while Date() < renderEnd { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No menu fixture bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            assert(bitmap.pixelsWide == 320 * scale && bitmap.pixelsHigh == 112 * scale, "Fixture must render at its requested physical density")
            let scaledOutput = output.deletingPathExtension().appendingPathExtension("\(scale)x.png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: scaledOutput)
            if scale == 2 { try bitmap.representation(using: .png, properties: [:])!.write(to: output) }
            // Inspect actual popover trigger ink, not the SVG or the image cache.
            for row in 0..<2 {
                for column in 0..<4 {
                    var bright = 0, colored = 0
                    var coreLow: CGFloat = 0, coreSpread: CGFloat = 1
                    let rect = CGRect(x: column * 80 + 12, y: row * 56 + 8, width: 56, height: 40)
                    for y in Int(rect.minY) * scale..<Int(rect.maxY) * scale {
                        for x in Int(rect.minX) * scale..<Int(rect.maxX) * scale {
                            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                            let low = min(color.redComponent, color.greenComponent, color.blueComponent)
                            let spread = max(color.redComponent, color.greenComponent, color.blueComponent) - low
                            if low > (row == 0 ? 0.66 : 0.29) { bright += 1 }
                            if low > coreLow { coreLow = low; coreSpread = spread }
                            // Gray backgrounds cannot tint neutral antialiasing. Capture's
                            // purple background does, so its white stroke core is checked below.
                            if column > 0 && low > 0.20 && spread > 0.05 { colored += 1 }
                        }
                    }
                    assert(bright >= 8 * scale, "Dark popover \(row == 0 ? "enabled" : "disabled") column \(column) at \(scale)× must retain visible light glyph ink, found \(bright)")
                    assert(colored == 0, "Popover glyphs on gray must retain neutral ink at \(scale)×, column \(column): \(colored) colored pixels")
                    if row == 0 {
                        assert(coreLow > (column == 0 ? 0.9 : 0.78), "Enabled glyph must retain a light stroke core at \(scale)×, column \(column): \(coreLow)")
                        assert(coreSpread < (column == 0 ? 0.08 : 0.04), "Enabled white/gray stroke core must remain neutral at \(scale)×, column \(column): \(coreSpread)")
                    }
                }
            }
        }
        print("PASS actual NSHostingView popover-trigger SVG-path contrast, enabled and disabled at 1×/2×, Capture white stroke core / neutral Export / Stroke / Font")
    }

}


private struct MenuContrastFixture: View {
    var body: some View {
        VStack(spacing: 0) {
            menuRow(enabled: true)
            menuRow(enabled: false)
        }.frame(width: 320, height: 112).background(Color(white: 0.13)).preferredColorScheme(.dark)
    }
    func menuRow(enabled: Bool) -> some View {
        HStack(spacing: 0) {
            menu("chevron", color: .white).background(Color(red: 0.55, green: 0.46, blue: 0.92))
            menu("export")
            menu("chevron")
            menu("chevron")
        }.disabled(!enabled)
    }
    func menu(_ icon: String, color: Color = Color(white: 0.84)) -> some View {
        ToolActionMenu("Fixture menu", actions: [ToolMenuAction("Fixture action") {}]) { ToolIcon(name: icon, size: 24, menuGlyph: true, menuColor: color).frame(width: 60, height: 40) }.frame(width: 80, height: 56)
    }
}
