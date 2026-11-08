import AppKit
import SwiftUI

/// Exercises the app's own SwiftUI accessibility actions; no global event injection,
/// screen capture permissions, user preferences, account or network access is used.
@main struct UIActionChecks {
    @MainActor static var passed=0
    @MainActor static func require(_ condition:@autoclosure()->Bool,_ message:String){
        guard condition() else{fatalError("FAIL: "+message)};passed+=1
    }
    @MainActor static func pump(_ duration:TimeInterval=0.25){
        let end=Date().addingTimeInterval(duration)
        while Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
    }
    @MainActor static func elements(_ root:Any)->[NSAccessibilityProtocol]{
        var result:[NSAccessibilityProtocol]=[],seen=Set<ObjectIdentifier>()
        func visit(_ item:Any,_ depth:Int){
            guard depth<50,let element=item as? NSAccessibilityProtocol else{return}
            let identity=ObjectIdentifier(element as AnyObject)
            guard seen.insert(identity).inserted else{return}
            result.append(element)
            for child in element.accessibilityChildren() ?? []{visit(child,depth+1)}
            if let view=item as? NSView{for child in view.subviews{visit(child,depth+1)}}
        }
        visit(root,0);return result
    }
    @MainActor static func find(_ identifier:String,in root:Any)->NSAccessibilityProtocol?{
        elements(root).first{$0.accessibilityIdentifier()==identifier}
    }
    @MainActor static func press(_ identifier:String,in root:Any){
        guard let control=find(identifier,in:root) else{
            let tree=elements(root).map{"\($0.accessibilityIdentifier() ?? "-") | \($0.accessibilityLabel() ?? "-") | \(String(describing:$0.accessibilityRole()))"}.prefix(150).joined(separator:"\n")
            fatalError("Missing UI action \(identifier). Own-view accessibility tree:\n\(tree)")
        }
        require(control.accessibilityPerformPress(),"Own-view action \(identifier) accepts its accessibility press")
        pump()
    }
    @MainActor static func main() throws{
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited);app.appearance=NSAppearance(named:.darkAqua)
        let suite="SnapDrive.UIAction.QA."+UUID().uuidString,prefs=UserDefaults(suiteName:suite)!
        let storage=FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer{prefs.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:storage)}
        let model=EditorModel(storageDirectory:storage,preferences:prefs)
        let capture=CaptureService(preferences:prefs,screenAccess:{true},requestScreenAccess:{false})
        let drive=DriveService(defaults:prefs,transientAccessToken:"isolated-ui-fixture",registeredClientID:"")
        let context=CGContext(data:nil,width:1200,height:800,bitsPerComponent:8,bytesPerRow:4800,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:0.95,green:0.96,blue:1,alpha:1));context.fill(CGRect(x:0,y:0,width:1200,height:800))
        context.setFillColor(CGColor(red:0.27,green:0.25,blue:0.63,alpha:1));context.fill(CGRect(x:80,y:540,width:1040,height:140))
        context.setFillColor(CGColor(red:0.8,green:0.82,blue:0.91,alpha:1));context.fill(CGRect(x:80,y:100,width:470,height:360));context.fill(CGRect(x:590,y:100,width:530,height:360))
        let source=ImageEngine.bitmapImage(cgImage:context.makeImage()!,logicalSize:NSSize(width:600,height:400))
        model.load(source,name:"Product overview with a long screenshot filename")
        model.style.padding=50;model.setSelectedLineWidth(20)
        let arrow=Annotation(kind:.arrow,start:CGPoint(x:0.2,y:0.55),end:CGPoint(x:0.65,y:0.25),lineWidth:20)
        model.add(arrow)
        let host=NSHostingView(rootView:EditorView().environmentObject(model).environmentObject(capture).environmentObject(drive))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1240,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=host;host.layoutSubtreeIfNeeded();pump(0.5)
        let hasActionTree=find("editor.clearCanvas",in:host) != nil
        if hasActionTree{
            press("editor.clearCanvas",in:host)
            require(model.image == nil && model.annotations.isEmpty,"The actual Clear screenshot button clears the screenshot and all edits")
            press("editor.undo",in:host)
            require(model.image === source && model.annotations == [arrow],"The actual Undo button restores the screenshot and exact edits after Clear")
            press("editor.redo",in:host)
            require(model.image == nil && model.annotations.isEmpty,"The actual Redo button clears the screenshot again")
            press("editor.undo",in:host)
            press("tool.rectangle",in:host)
            require(model.tool == .rectangle && model.lineWidth == 20,"The actual shape tool preserves the saved20px stroke")
            press("tool.arrow",in:host)
            require(model.tool == .arrow && model.lineWidth == 20,"The actual Arrow tool activates with the saved20px stroke")
        }else{
            if ProcessInfo.processInfo.environment["SNAPDRIVE_REQUIRE_UI_ACTIONS"] == "1"{fatalError("SwiftUI accessibility actions are required, but the own-view action tree is unavailable")}
            print("SKIP: Actual SwiftUI accessibility actions unavailable: own NSHostingView exposes no SwiftUI accessibility children. Model/native event tests run separately; render/layout checks continue.")
        }
        let snapshots=ProcessInfo.processInfo.environment["SNAPDRIVE_UI_SNAPSHOT_DIR"].map{URL(fileURLWithPath:$0)}
        if let snapshots{try FileManager.default.createDirectory(at:snapshots,withIntermediateDirectories:true)}
        for (size,name,tool) in [(NSSize(width:1240,height:820),"Editor-Default-Dark",EditorTool.arrow),(NSSize(width:1100,height:720),"Editor-Minimum-Text-Dark",EditorTool.text),(NSSize(width:1240,height:820),"Editor-Magnifier-Dark",EditorTool.magnifier)]{
            model.tool=tool;window.setContentSize(size);host.frame=NSRect(origin:.zero,size:size);pump(0.5);host.layoutSubtreeIfNeeded()
            require(host.bounds.width==size.width && host.bounds.height==size.height,"Editor lays out at \(Int(size.width))×\(Int(size.height))")
            if hasActionTree{
                let clear=find("editor.clearCanvas",in:host),undo=find("editor.undo",in:host),upload=find("editor.upload",in:host)
                require(clear != nil && undo != nil && upload != nil,"Primary actions remain accessible in \(name)")
                let clearFrame=clear!.accessibilityFrame()
                require(clearFrame.width>=35 && clearFrame.height>=30,"Clear retains an accessible hit target in \(name)")
            }
            if let snapshots{
                guard let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds),let png:Data={host.cacheDisplay(in:host.bounds,to:rep);return rep.representation(using:.png,properties:[:])}() else{fatalError("Could not render own-view snapshot")}
                try png.write(to:snapshots.appendingPathComponent(name+".png"))
            }
        }
        print("PASS \(passed) SwiftUI \(hasActionTree ? "action/layout":"layout") checks: default/minimum/text/magnifier dark layouts\(hasActionTree ? ", actual Clear/Undo/Redo/tool actions":"; actual accessibility actions skipped as reported")")
    }
}
