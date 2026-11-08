import AppKit
import SwiftUI

@main struct InteractionChecks {
    @MainActor static var passed = 0
    @MainActor static func require(_ ok: @autoclosure () -> Bool, _ message: String) {
        guard ok() else { fatalError("FAIL: " + message) }; passed += 1
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnapDrive-interaction-" + UUID().uuidString)
        let suite = "SnapDrive.interaction." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); preferences.removePersistentDomain(forName: suite) }
        var clipboard: [String] = []
        let recognitionProbe = InteractionRecognitionProbe()
        let m = EditorModel(storageDirectory: root, preferences: preferences, clipboardWriter: { clipboard.append($0) }, recognizeText: { recognitionProbe.recognize($0) })
        let ctx = CGContext(data: nil,width: 600,height: 400,bitsPerComponent: 8,bytesPerRow: 2400,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor);ctx.fill(CGRect(x:0,y:0,width:600,height:400))
        let originalImage = NSImage(cgImage:ctx.makeImage()!,size:NSSize(width:300,height:200))
        m.load(originalImage)
        m.style.padding=30;m.style.radius=0;m.style.shadow=0
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:650),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let host=EditorCanvasScrollView(model:m);host.frame=NSRect(x:0,y:0,width:900,height:650);window.contentView=host
        host.layoutSubtreeIfNeeded();host.canvas.updateGeometry(viewport:CGSize(width:900,height:650))
        let v=host.canvas
        func point(_ x:Double,_ y:Double)->CGPoint { EditorInteraction.point(CGPoint(x:x,y:y),in:v.sourceFrame) }
        func mouse(_ type:NSEvent.EventType,_ p:CGPoint,_ clicks:Int=1,_ modifiers:NSEvent.ModifierFlags=[]) {
            let location=v.convert(p,to:nil)
            let event=NSEvent.mouseEvent(with:type,location:location,modifierFlags:modifiers,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:clicks,pressure:1)!
            switch type {case .leftMouseDown:v.mouseDown(with:event);case .leftMouseDragged:v.mouseDragged(with:event);default:v.mouseUp(with:event)}
        }
        func key(_ code:UInt16,_ chars:String="",_ modifiers:NSEvent.ModifierFlags=[]) {
            v.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:chars,charactersIgnoringModifiers:chars,isARepeat:false,keyCode:code)!)
        }
        func draw(_ tool:EditorTool,_ a:CGPoint,_ b:CGPoint) {
            m.tool=tool;mouse(.leftMouseDown,a);mouse(.leftMouseDragged,b);mouse(.leftMouseUp,b)
        }
        func captureArrowPixels()->(bounds:CGRect,count:Int) {
            let representation=v.bitmapImageRepForCachingDisplay(in:v.bounds)!
            v.cacheDisplay(in:v.bounds,to:representation)
            let cg=representation.cgImage!,width=cg.width,height=cg.height
            let pixels=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            pixels.draw(cg,in:CGRect(x:0,y:0,width:width,height:height))
            let data=pixels.data!.assumingMemoryBound(to:UInt8.self)
            var minX=width,minY=height,maxX=0,maxY=0,count=0
            for y in 0..<height{for x in 0..<width{
                let i=(y*width+x)*4
                if data[i]>200 && data[i+1]<150 && data[i+2]<180{minX=min(minX,x);minY=min(minY,y);maxX=max(maxX,x);maxY=max(maxY,y);count+=1}
            }}
            return (count>0 ? CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1):.zero,count)
        }
        require(m.tool == .arrow,"An opened image starts ready to draw arrows")
        m.setSelectedLineWidth(20)
        mouse(.leftMouseDown,point(0.1,0.2));mouse(.leftMouseDragged,point(0.4,0.3))
        let draftArrow=captureArrowPixels()
        mouse(.leftMouseUp,point(0.4,0.3));m.selectAnnotation(nil)
        let committedArrow=captureArrowPixels()
        require(draftArrow.count>100 && committedArrow.count>100,"Live and committed arrows both render a visible filled shape")
        require(abs(draftArrow.bounds.minX-committedArrow.bounds.minX)<=3 && abs(draftArrow.bounds.minY-committedArrow.bounds.minY)<=3 && abs(draftArrow.bounds.maxX-committedArrow.bounds.maxX)<=3 && abs(draftArrow.bounds.maxY-committedArrow.bounds.maxY)<=3,"Live arrow stroke and head occupy the same pixels as the committed arrow")
        require(Double(draftArrow.count)/Double(committedArrow.count)>0.85 && Double(draftArrow.count)/Double(committedArrow.count)<1.15,"Live arrow uses the committed filled head and full20px stroke rather than a thin dashed outline")
        let firstContinuous=m.annotations.last!
        require(m.tool == .arrow && firstContinuous.lineWidth == 20,"Drawing an arrow keeps Arrow active and the saved20px stroke")
        mouse(.leftMouseDown,point(0.55,0.65));mouse(.leftMouseDragged,point(0.85,0.8));mouse(.leftMouseUp,point(0.85,0.8))
        require(m.annotations.count == 2 && m.tool == .arrow && m.annotations[0] == firstContinuous,"A second drag adds another arrow without moving the first")
        let continuousUndo=m.undoStack.count
        mouse(.leftMouseDown,point(0.15,0.8));mouse(.leftMouseDragged,point(0.5,0.8));key(53);mouse(.leftMouseUp,point(0.5,0.8))
        require(m.annotations.count == 2 && m.undoStack.count == continuousUndo && m.tool == .arrow,"Escape cancels an arrow draft without an orphan or undo entry")
        key(18,"1")
        require(m.tool == .select,"1 switches continuous Arrow drawing to Select")
        mouse(.leftMouseDown,point(0.25,0.25));mouse(.leftMouseUp,point(0.25,0.25))
        require(m.selectedID == firstContinuous.id,"Select can pick the first arrow after continuous drawing")
        key(51,"\u{7f}")
        require(m.annotations.count == 1 && m.annotations[0].id != firstContinuous.id,"Delete removes only the arrow picked with Select")
        m.load(originalImage);host.reload()
        mouse(.leftMouseDown,point(0.2,0.3));mouse(.leftMouseDragged,point(0.65,0.5),1,[.shift]);mouse(.leftMouseUp,point(0.65,0.5),1,[.shift])
        let straight=m.annotations.last!
        require(abs(straight.start.y-straight.end.y)<0.00001,"Shift snaps a shallow arrow to horizontal")
        mouse(.leftMouseDown,point(0.25,0.2));mouse(.leftMouseDragged,point(0.55,0.6),1,[.shift]);mouse(.leftMouseUp,point(0.55,0.6),1,[.shift])
        let diagonal=m.annotations.last!
        require(abs(abs(diagonal.end.x-diagonal.start.x)*600-abs(diagonal.end.y-diagonal.start.y)*400)<0.001,"Shift snaps a diagonal to45degrees in native pixels")
        let edge=EditorInteraction.constrainedArrowEnd(from:point(0.8,0.8),to:point(1.7,1.6),in:v.sourceFrame)
        require(v.sourceFrame.insetBy(dx:-0.001,dy:-0.001).contains(edge) && abs(abs(edge.x-point(0.8,0.8).x)-abs(edge.y-point(0.8,0.8).y))<0.001,"Shift keeps its snapped direction when a drag reaches the image edge")
        m.load(originalImage);host.reload()
        let shortcutTarget=Annotation(kind:.rectangle,start:CGPoint(x:0.2,y:0.2),end:CGPoint(x:0.4,y:0.4))
        m.add(shortcutTarget)
        for (letter,code,tool) in [("v",UInt16(9),EditorTool.select),("a",0,.arrow),("t",17,.text),("r",15,.rectangle),("e",14,.ellipse),("x",7,.redact),("p",35,.pixelate),("c",8,.crop),("b",11,.blur),("o",31,.textselect),("m",46,.magnifier)]{
            m.selectAnnotation(shortcutTarget.id);key(code,letter)
            require(m.tool == tool && m.selectedID == (tool == .select ? shortcutTarget.id:nil),"Letter\(letter.uppercased()) selects\(tool.title) with the appropriate object selection")
            key(code,letter.uppercased(),[.shift])
            require(m.tool == tool,"Shift-\(letter.uppercased()) keeps the same tool shortcut")
        }
        draw(.arrow,point(0.2,0.6),point(0.6,0.75));let shortcutArrow=m.annotations.last!
        key(9,"v");require(m.tool == .select && m.selectedID == shortcutArrow.id,"V preserves the just-drawn arrow so its selection handles are immediately available")
        key(18,"1");require(m.selectedID == shortcutArrow.id,"The numeric Select shortcut preserves the same object selection")
        key(51,"\u{7f}");require(!m.annotations.contains(where:{$0.id == shortcutArrow.id}) && m.annotations.contains(where:{$0.id == shortcutTarget.id}),"Delete immediately after Select removes the selected arrow and preserves other annotations")
        m.load(originalImage);host.reload()
        for tool in [EditorTool.arrow,.rectangle,.ellipse,.redact,.pixelate,.blur] {
            let count=m.annotations.count
            draw(tool,point(0.15,0.2),point(0.6,0.65))
            require(m.annotations.count==count+1,"Native draw creates \(tool)")
            require(m.selectedID==m.annotations.last?.id,"New \(tool) is selected")
            key(51,"\u{7f}");require(m.annotations.count==count,"Backspace deletes \(tool)")
            m.undo();require(m.annotations.count==count+1 && m.selectedID==m.annotations.last?.id,"Undo restores annotation and selection")
            key(117);require(m.annotations.count==count,"Forward delete removes \(tool)")
        }
        draw(.arrow,point(0.1,0.2),point(0.6,0.7));let arrow=m.annotations.last!
        m.tool = .select
        mouse(.leftMouseDown,point(0.1,0.7));mouse(.leftMouseUp,point(0.1,0.7))
        require(m.selectedID==nil,"Arrow bounding-box blank space does not select")
        mouse(.leftMouseDown,point(0.35,0.45));mouse(.leftMouseUp,point(0.35,0.45))
        require(m.selectedID==arrow.id,"Arrow shaft selects")
        let undoCount=m.undoStack.count
        mouse(.leftMouseDown,point(0.35,0.45))
        for i in 1...5 {mouse(.leftMouseDragged,point(0.35+Double(i)*0.02,0.45))}
        mouse(.leftMouseUp,point(0.45,0.45))
        require(m.undoStack.count==undoCount+1,"Five drag updates produce one undo")
        require(abs(m.annotations.last!.start.x-0.2)<0.0001,"Native drag preserves grab offset")
        m.undo();require(m.annotations.last==arrow,"Undo restores complete drag")
        m.redo();require(abs(m.annotations.last!.start.x-0.2)<0.0001,"Redo restores complete drag")
        let beforeCancel=m.annotations
        mouse(.leftMouseDown,point(0.45,0.45));mouse(.leftMouseDragged,point(0.5,0.5));key(53)
        require(m.annotations==beforeCancel,"Escape cancels active drag")
        m.tool = .text;mouse(.leftMouseDown,point(0.2,0.15))
        guard let text=v.subviews.compactMap({$0 as? NSTextView}).first else {fatalError("Inline text editor missing")}
        require(text.string.isEmpty,"New text editor starts empty")
        require(window.firstResponder === text,"Inline text editor owns keyboard focus")
        text.insertText("Hello123",replacementRange:NSRange(location:0,length:0));text.deleteBackward(nil)
        require(text.string=="Hello12","Text Backspace edits characters")
        let countBeforeText=m.annotations.count
        require(countBeforeText==1,"Typing does not prematurely create annotation")
        text.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!)
        require(m.annotations.count==2 && m.annotations.last?.text=="Hello12","Return commits typed text once")
        let textID=m.annotations.last!.id
        require(window.firstResponder === v,"Text commit restores canvas focus")
        m.tool = .select;mouse(.leftMouseDown,point(0.205,0.16),2)
        guard let editor=v.subviews.compactMap({$0 as? NSTextView}).first else {fatalError("Double-click editor missing")}
        require(editor.string=="Hello12","Double-click opens existing text")
        editor.string="Changed"
        v.cancelInlineText();require(m.annotations.last?.text=="Hello12","Escape/cancel preserves existing text")
        v.beginInlineText(at:CGPoint(x:0.2,y:0.15),replacing:m.annotations.last)
        let editing=v.subviews.compactMap({$0 as? NSTextView}).first!;editing.string="Updated label"
        v.commitInlineText();require(m.annotations.last?.text=="Updated label" && m.annotations.last?.id==textID,"Text edit retains identity")
        m.undo();require(m.annotations.last?.text=="Hello12","Undo restores old text")
        m.selectAnnotation(textID);m.setSelectedFontSize(48);require(m.annotations.last?.fontSize==48,"Font change applies immediately")
        m.setSelectedColor(.blue);require(m.annotations.last?.colorHex==Color.blue.hexString,"Color change applies immediately")
        m.selectAnnotation(arrow.id);m.setSelectedLineWidth(10);require(m.annotations.first?.lineWidth==10,"Line width applies immediately")
        let beforeNudge=m.annotations.first!.start.x;key(124)
        require(abs(m.annotations.first!.start.x-beforeNudge-1.0/600)<0.0001,"Arrow key nudges one native pixel")
        for zoom in [0.0,0.5,1,2] {m.zoom=zoom;host.reload();let p=point(0.31,0.62);let n=EditorInteraction.normalized(p,in:v.sourceFrame);require(abs(n.x-0.31)<0.0001 && abs(n.y-0.62)<0.0001,"Coordinate roundtrip at zoom \(zoom)")}
        let reversed=Annotation(kind:.rectangle,start:CGPoint(x:0.8,y:0.8),end:CGPoint(x:0.2,y:0.2))
        let unchanged=EditorInteraction.resized(reversed,handle:.bottomRight,to:CGPoint(x:0.8,y:0.8))
        let rb=EditorInteraction.normalizedBounds(unchanged,pixels:CGSize(width:600,height:400))
        require(abs(rb.minX-0.2)<0.00001 && abs(rb.minY-0.2)<0.00001 && abs(rb.width-0.6)<0.00001 && abs(rb.height-0.6)<0.00001,"Reverse resize keeps opposite corner stable")
        let count=m.annotations.count; m.tool = .text;mouse(.leftMouseDown,point(0.8,0.8));v.cancelInlineText();require(m.annotations.count==count,"Cancel new text adds nothing")
        m.tool = .rectangle;mouse(.leftMouseDown,point(0.5,0.5));mouse(.leftMouseUp,point(0.5,0.5));require(m.annotations.count==count,"Click without drag creates no zero-size rectangle")

        func resetDocument() {
            v.cancelInlineText(); m.load(originalImage)
            m.style.padding = 30; m.style.radius = 0; m.style.shadow = 0
            host.reload(); v.updateGeometry(viewport: CGSize(width: 900, height: 650))
            window.makeFirstResponder(v)
        }
        func startText(_ value: String, at location: CGPoint = CGPoint(x: 0.15, y: 0.15)) -> NSTextView {
            m.tool = .text; mouse(.leftMouseDown, point(location.x, location.y))
            guard let editor = v.subviews.compactMap({ $0 as? NSTextView }).first else { fatalError("Inline editor missing") }
            editor.string = value
            return editor
        }
        func hasInlineEditor() -> Bool { v.subviews.contains(where: { $0 is NSTextView }) }

        resetDocument()
        let typingEditor=startText("")
        for (letter,code) in [("t",UInt16(17)),("a",0),("r",15)]{
            typingEditor.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:letter,charactersIgnoringModifiers:letter,isARepeat:false,keyCode:code)!)
        }
        require(typingEditor.string == "tar" && window.firstResponder === typingEditor,"Tool shortcut letters type normal characters while inline text owns focus")
        require(m.tool == .text && m.annotations.isEmpty,"Typing T/A/R never changes tools or creates an annotation before commit")
        v.commitInlineText()
        require(m.annotations.count == 1 && m.annotations[0].text == "tar","Typed shortcut letters commit as one complete text annotation")

        // The click that ends a text edit must not begin a second edit or drag the saved label.
        resetDocument()
        _ = startText("Saved by outside click")
        let outsideUndo = m.undoStack.count
        mouse(.leftMouseDown, point(0.8, 0.75))
        mouse(.leftMouseDragged, point(0.9, 0.85)); mouse(.leftMouseUp, point(0.9, 0.85))
        require(m.annotations.count == 1 && m.annotations[0].text == "Saved by outside click", "Outside click and drag save inline text once")
        require(m.tool == .select && !hasInlineEditor(), "Outside click returns to selection without opening another text box")
        require(abs(m.annotations[0].start.x - 0.15) < 0.0001 && abs(m.annotations[0].start.y - 0.15) < 0.0001, "Outside drag does not move the label just committed")
        require(m.undoStack.count == outsideUndo + 1, "Outside click creates one undo entry")
        mouse(.leftMouseUp, point(0.9, 0.85))
        require(m.annotations.count == 1 && m.undoStack.count == outsideUndo + 1, "Repeated mouse-up cannot duplicate the text commit")

        // Editing an existing label preserves its ID and leaves the original point unchanged.
        let outsideTextID = m.annotations[0].id
        m.tool = .select; mouse(.leftMouseDown, point(0.16, 0.16), 2)
        guard let outsideEdit = v.subviews.compactMap({ $0 as? NSTextView }).first else { fatalError("Existing label editor missing") }
        outsideEdit.string = "Changed by outside click"
        let existingUndo = m.undoStack.count
        mouse(.leftMouseDown, point(0.85, 0.8)); mouse(.leftMouseUp, point(0.85, 0.8))
        require(m.annotations.count == 1 && m.annotations[0].id == outsideTextID && m.annotations[0].text == "Changed by outside click", "Outside click updates an existing label without adding a duplicate")
        require(m.undoStack.count == existingUndo + 1, "Existing-label edit creates one undo entry")
        m.undo(); require(m.annotations[0].id == outsideTextID && m.annotations[0].text == "Saved by outside click", "Undo restores the original label with its identity")

        // An inspector field taking focus must retain it after the inline text is saved.
        resetDocument()
        _ = startText("Focus transfer")
        let inspector = NSTextField(frame: CGRect(x: 8, y: 8, width: 180, height: 24))
        host.addSubview(inspector)
        let focusUndo = m.undoStack.count
        require(window.makeFirstResponder(inspector), "Inspector field can receive focus")
        require(m.annotations.count == 1 && m.annotations[0].text == "Focus transfer" && !hasInlineEditor(), "Focus loss saves text synchronously")
        require(window.firstResponder !== v && inspector.currentEditor() != nil, "Committing on focus loss does not steal focus back from inspector")
        require(m.undoStack.count == focusUndo + 1, "Focus transfer commits exactly once")
        inspector.removeFromSuperview(); window.makeFirstResponder(v)
        m.commitActiveText()
        require(m.undoStack.count == focusUndo + 1, "Later commit notification cannot repeat a focus-loss save")
        await nextUIEventTurn()

        // Tool buttons and an export snapshot must see all text the user has typed.
        resetDocument()
        _ = startText("Saved before tool switch")
        let toolUndo = m.undoStack.count
        m.commitActiveText()
        m.selectAnnotation(nil); m.tool = .rectangle
        require(m.annotations.count == 1 && m.annotations[0].text == "Saved before tool switch" && m.tool == .rectangle, "Toolbar switch saves text before activating the chosen tool")
        require(m.undoStack.count == toolUndo + 1 && !hasInlineEditor(), "Toolbar switch saves once and removes the editor")
        resetDocument()
        let emptyExport = m.output()!.0
        _ = startText("Included in export")
        let snapshot = m.output()
        require(snapshot != nil && snapshot!.0 != emptyExport && m.annotations.count == 1 && m.annotations[0].text == "Included in export", "Export snapshot synchronously includes uncommitted text")
        require(!hasInlineEditor() && m.undoStack.count == 1, "Export notification commits text exactly once")
        _ = m.output(); require(m.undoStack.count == 1, "Repeated export does not add undo entries")

        resetDocument()
        _ = startText("  \n  ")
        mouse(.leftMouseDown, point(0.8, 0.7)); mouse(.leftMouseUp, point(0.8, 0.7))
        require(m.annotations.isEmpty && m.undoStack.isEmpty && !hasInlineEditor(), "Empty outside-click edit leaves no annotation or undo entry")
        let cancelledEditor = startText("This must not be saved")
        cancelledEditor.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!)
        require(m.annotations.isEmpty && m.undoStack.isEmpty && !hasInlineEditor(), "Escape cancels new text without committing")

        // All shape/privacy tools accept custom widths, including bounds, in either drag direction.
        resetDocument()
        for (requested, expected) in [(37.5,37.5),(-2.0,0.5),(2500.0,1000.0),(Double.nan,4.0),(Double.infinity,4.0)] {
            m.selectAnnotation(nil); m.setSelectedLineWidth(requested)
            require(m.lineWidth == expected, "Custom width is bounded and finite")
            for tool in [EditorTool.arrow,.rectangle,.ellipse,.redact,.pixelate,.blur] {
                let oldCount = m.annotations.count
                draw(tool, point(0.7,0.7), point(0.2,0.25))
                require(m.annotations.count == oldCount + 1 && m.annotations.last?.kind == tool.annotationKind, "Reverse drag creates \(tool) at custom width")
                require(m.annotations.last?.lineWidth == expected, "New \(tool) retains custom width \(expected)")
                m.removeSelected()
            }
        }
        m.tool = .select; m.selectAnnotation(nil)
        mouse(.leftMouseDown, point(0.95,0.95)); mouse(.leftMouseUp, point(0.95,0.95))
        require(m.annotations.isEmpty, "Selection on blank canvas adds no annotation")

        // Native Select text drag must crop the selected pixels and copy recognized text once.
        resetDocument()
        let recognizedBefore = recognitionProbe.sizes.count, clipboardBefore = clipboard.count
        let annotationsBefore = m.annotations
        draw(.textselect, point(0.2,0.3), point(0.6,0.7))
        await waitForRecognition(m)
        require(recognitionProbe.sizes.count == recognizedBefore + 1, "Text selection starts recognition once")
        let selectedPixels = recognitionProbe.sizes.last!
        require(abs(selectedPixels.width - 240) <= 2 && abs(selectedPixels.height - 160) <= 2, "Text selection recognizes only selected native pixels")
        require(clipboard.count == clipboardBefore + 1 && clipboard.last == "Selected fixture text\nSecond fixture line", "Select text copies recognized lines exactly once")
        require(m.annotations == annotationsBefore && !m.showText, "Text selection adds no annotation and needs no extra dialog")
        require(m.toast == "Text copied", "Selected-text copy shows success feedback")
        let mapped = m.recognized.first!.rect
        require(abs(mapped.minX - 0.24) < 0.0001 && abs(mapped.minY - 0.38) < 0.0001, "Recognized text positions map back to source coordinates")
        recognitionProbe.setLines([])
        let noTextClipboard = clipboard.count
        draw(.textselect, point(0.4,0.4), point(0.7,0.6)); await waitForRecognition(m)
        require(clipboard.count == noTextClipboard && m.status.lowercased().contains("no text"), "Empty recognition preserves clipboard and explains that no text was found")
        let callsBeforeTiny = recognitionProbe.sizes.count
        m.tool = .textselect; mouse(.leftMouseDown, point(0.5,0.5)); mouse(.leftMouseUp, point(0.5,0.5))
        require(recognitionProbe.sizes.count == callsBeforeTiny, "Zero-size text selection does not start recognition")

        // Crop remains undoable after moving from drawing/text selection tools.
        resetDocument()
        draw(.rectangle, point(0.3,0.3), point(0.6,0.6))
        let beforeCrop = m.annotations
        draw(.crop, point(0.25,0.25), point(0.75,0.75))
        let cropPixels = ImageEngine.pixelSize(m.image!)
        require(abs(cropPixels.width - 300) <= 2 && abs(cropPixels.height - 200) <= 2 && m.annotations.isEmpty, "Native crop uses selected source pixels and flattens annotations; got \(cropPixels), \(m.annotations.count) annotations, status=\(m.status)")
        m.undo()
        require(ImageEngine.pixelSize(m.image!) == CGSize(width:600,height:400) && m.annotations == beforeCrop, "Undo crop restores image and annotation layers")

        resetDocument()
        draw(.redact, point(0.7,0.65), point(0.9,0.85))
        let coveredAnnotation = m.annotations[0]
        _ = startText("Finish without dragging another annotation")
        let coveredUndo = m.undoStack.count
        mouse(.leftMouseDown, point(0.8,0.75)); mouse(.leftMouseDragged, point(0.85,0.8)); mouse(.leftMouseUp, point(0.85,0.8))
        require(m.annotations.first(where: { $0.id == coveredAnnotation.id }) == coveredAnnotation, "The click ending text editing cannot start dragging another annotation beneath it")
        require(m.annotations.count == 2 && m.undoStack.count == coveredUndo + 1, "Closing text over another annotation still commits only one text edit")

        // AppKit can transfer first responder before delivering the same mouse-down to the canvas.
        resetDocument()
        draw(.redact, point(0.7,0.65), point(0.9,0.85))
        let windowTarget = m.annotations[0]
        _ = startText("Saved during AppKit focus transfer")
        let windowFocusUndo = m.undoStack.count
        require(window.makeFirstResponder(v), "AppKit can transfer focus before canvas mouse-down")
        require(m.annotations.count == 2 && !hasInlineEditor(), "Pre-event focus transfer saves text synchronously")
        mouse(.leftMouseDown, point(0.8,0.75)); mouse(.leftMouseDragged, point(0.85,0.8)); mouse(.leftMouseUp, point(0.85,0.8))
        require(m.annotations.first(where: { $0.id == windowTarget.id }) == windowTarget && m.undoStack.count == windowFocusUndo + 1, "The same focus-transfer click is consumed without dragging another annotation")
        require(m.tool == .select && !hasInlineEditor(), "Pre-event focus transfer cannot open a replacement text editor")
        await nextUIEventTurn()

        // Magnifiers are editable native-pixel circles, independent of screenshot aspect and canvas zoom.
        resetDocument()
        m.setSelectedMagnification(2)
        m.tool = .magnifier
        mouse(.leftMouseDown, point(0.5,0.5)); mouse(.leftMouseUp, point(0.5,0.5))
        require(m.annotations.count == 1 && m.annotations[0].kind == .magnifier, "Single click places a default magnifier")
        let defaultLens = m.annotations[0], lensPixels = ImageEngine.pixelSize(m.image!)
        let defaultCircle = EditorInteraction.normalizedBounds(defaultLens, pixels: lensPixels)
        require(defaultCircle.width * lensPixels.width > 8 && abs(defaultCircle.width * lensPixels.width - defaultCircle.height * lensPixels.height) < 0.001, "Default magnifier is circular in native pixels")
        require(abs(defaultCircle.midX - 0.5) < 0.0001 && abs(defaultCircle.midY - 0.5) < 0.0001, "Default lens is centered at the clicked source point")
        require(m.selectedMagnifier?.id == defaultLens.id && m.tool == .select && defaultLens.magnification == 2, "Placed lens is selected with default zoom and returns to selection")
        require(m.undoStack.count == 1, "Default lens placement creates one undo step")
        key(46, "m")
        require(m.tool == .magnifier && m.selectedID == nil, "M selects the magnifier tool")
        draw(.magnifier, point(0.15,0.2), point(0.45,0.45))
        require(m.annotations.count == 2 && m.annotations.last?.kind == .magnifier, "Dragging creates a second magnifier")
        let draggedLens = m.annotations.last!, draggedCircle = EditorInteraction.normalizedBounds(draggedLens, pixels: lensPixels)
        require(abs(draggedCircle.width * lensPixels.width - draggedCircle.height * lensPixels.height) < 0.001, "Unequal-axis drag still makes a native-pixel circle")
        m.selectAnnotation(nil)
        let outsideCircle = CGPoint(x: draggedCircle.minX + draggedCircle.width * 0.04, y: draggedCircle.minY + draggedCircle.height * 0.04)
        mouse(.leftMouseDown, point(outsideCircle.x,outsideCircle.y)); mouse(.leftMouseUp, point(outsideCircle.x,outsideCircle.y))
        require(m.selectedID == nil, "Magnifier bounding-box corner outside the circle does not select it")
        let lensCenter = CGPoint(x: draggedCircle.midX, y: draggedCircle.midY)
        mouse(.leftMouseDown, point(lensCenter.x,lensCenter.y)); mouse(.leftMouseUp, point(lensCenter.x,lensCenter.y))
        require(m.selectedID == draggedLens.id, "Clicking the lens center selects it")
        let lensMoveUndo = m.undoStack.count
        mouse(.leftMouseDown, point(lensCenter.x,lensCenter.y))
        for step in 1...4 { mouse(.leftMouseDragged, point(lensCenter.x + Double(step) * 0.02, lensCenter.y + Double(step) * 0.015)) }
        mouse(.leftMouseUp, point(lensCenter.x + 0.08,lensCenter.y + 0.06))
        let movedLens = m.annotations.last!, movedCircle = EditorInteraction.normalizedBounds(movedLens, pixels: lensPixels)
        require(abs(movedCircle.midX - draggedCircle.midX - 0.08) < 0.0001 && abs(movedCircle.midY - draggedCircle.midY - 0.06) < 0.0001, "Dragging lens center moves the complete circle with its grab offset")
        require(abs(movedCircle.width - draggedCircle.width) < 0.0001 && m.undoStack.count == lensMoveUndo + 1, "Lens move preserves size and uses one undo for repeated mouse updates")
        m.undo(); require(m.annotations.last == draggedLens, "Undo restores lens move and complete geometry")
        m.redo(); require(m.annotations.last == movedLens, "Redo restores lens move")
        let resizeHandle = EditorInteraction.handles(movedLens, frame: v.sourceFrame, pixels: lensPixels).first(where: { $0.0 == .bottomRight })!.1
        let resizeTarget = CGPoint(x: resizeHandle.x + v.sourceFrame.width * 0.1, y: resizeHandle.y + v.sourceFrame.height * 0.15)
        let lensResizeUndo = m.undoStack.count
        mouse(.leftMouseDown, resizeHandle); mouse(.leftMouseDragged, resizeTarget); mouse(.leftMouseUp, resizeTarget)
        let resizedLens = m.annotations.last!, resizedCircle = EditorInteraction.normalizedBounds(resizedLens, pixels: lensPixels)
        require(resizedCircle.width > movedCircle.width && abs(resizedCircle.width * lensPixels.width - resizedCircle.height * lensPixels.height) < 0.001, "Corner resizing grows the magnifier without making an oval")
        require(abs(resizedCircle.minX - movedCircle.minX) < 0.0001 && abs(resizedCircle.minY - movedCircle.minY) < 0.0001 && m.undoStack.count == lensResizeUndo + 1, "Magnifier resize keeps the opposite corner and makes one undo step")
        m.undo(); require(m.annotations.last == movedLens, "Undo restores the resized lens")
        m.redo(); require(m.annotations.last == resizedLens, "Redo restores magnifier resize")
        let zoomUndo = m.undoStack.count
        m.setSelectedMagnification(4.5)
        require(m.selectedMagnifier?.magnification == 4.5 && m.magnification == 4.5 && m.undoStack.count == zoomUndo + 1, "Magnification control updates the selected lens and records one edit")
        require(EditorInteraction.normalizedBounds(m.annotations.last!, pixels: lensPixels) == resizedCircle, "Changing magnification keeps lens placement and size")
        m.undo(); require(m.selectedMagnifier?.magnification == 2 && m.magnification == 2, "Undo restores the previous magnification and control")
        m.redo(); require(m.selectedMagnifier?.magnification == 4.5 && m.magnification == 4.5, "Redo restores magnification and control")
        for (requested, expected) in [(-4.0,1.0),(30.0,8.0),(Double.nan,2.0),(Double.infinity,2.0)] {
            m.setSelectedMagnification(requested)
            require(m.selectedMagnifier?.magnification == expected && m.magnification == expected, "Magnifier zoom is finite and clamped to 1–8")
        }
        m.setSelectedMagnifierDiameter(200)
        let sizedLens = m.selectedMagnifier!, sizedCircle = EditorInteraction.normalizedBounds(sizedLens, pixels: lensPixels)
        require(abs(sizedCircle.width * lensPixels.width - 200) < 0.001 && abs(sizedCircle.height * lensPixels.height - 200) < 0.001, "Custom lens diameter uses native pixels on both axes")
        require(abs(m.magnifierDiameter - 200) < 0.001, "Lens diameter control reads the selected native size")
        let diameterUndo = m.undoStack.count
        m.setSelectedMagnifierDiameter(Double.nan)
        require(m.selectedMagnifier == sizedLens && m.undoStack.count == diameterUndo, "Invalid lens diameter cannot corrupt geometry or history")
        for zoom in [0.0,0.5,1.0,2.0] {
            m.zoom = zoom; host.reload()
            let displayCircle = EditorInteraction.bounds(sizedLens, frame: v.sourceFrame, pixels: lensPixels)
            require(abs(displayCircle.width - displayCircle.height) < 0.001, "Magnifier remains circular at canvas zoom \(zoom)")
            m.selectAnnotation(nil)
            let center = CGPoint(x: displayCircle.midX, y: displayCircle.midY)
            mouse(.leftMouseDown, center); mouse(.leftMouseUp, center)
            require(m.selectedID == sizedLens.id, "Magnifier center hit-test works at canvas zoom \(zoom)")
        }
        key(51, "\u{7f}")
        require(m.annotations.count == 1 && m.annotations[0].id == defaultLens.id, "Backspace deletes only the selected magnifier")
        m.undo(); require(m.annotations.last == sizedLens && m.selectedID == sizedLens.id, "Undo restores magnifier geometry, zoom, and selection")
        m.redo(); require(m.annotations.count == 1, "Redo deletes the magnifier again")

        // Clear includes an active draft, and undo must recover the complete text.
        resetDocument()
        draw(.rectangle, point(0.65,0.65), point(0.85,0.85))
        let beforeClear = m.annotations[0]
        _ = startText("Draft survives Clear and Undo")
        m.clearAnnotations()
        require(m.annotations.isEmpty && !hasInlineEditor() && m.selectedID == nil, "Clear saves the active text then removes every annotation and editor")
        require(m.tool == .select && m.toast?.contains("Annotations cleared") == true, "Clear returns to selection and provides visible feedback")
        m.undo()
        require(m.annotations.count == 2 && m.annotations[0] == beforeClear && m.annotations[1].text == "Draft survives Clear and Undo", "One undo of Clear restores the saved draft and existing annotation")
        m.redo()
        require(m.annotations.isEmpty && !hasInlineEditor(), "Redo of Clear removes the complete restored annotation set")

        // Clearing the whole canvas must commit a live text editor before taking
        // the undo snapshot, so the screenshot and its draft return together.
        resetDocument()
        m.selectAnnotation(nil);m.setSelectedLineWidth(20)
        draw(.rectangle,point(0.65,0.65),point(0.85,0.85))
        let canvasClearShape=m.annotations[0],canvasClearImage=m.image
        _ = startText("Draft survives Clear Canvas and Undo")
        m.clearCanvas()
        require(m.image == nil && m.annotations.isEmpty && !hasInlineEditor() && m.currentHistoryID == nil,"Clear Canvas closes active inline text and returns to an empty workspace")
        m.undo()
        require(m.image === canvasClearImage && m.annotations.count == 2 && m.annotations[0] == canvasClearShape && m.annotations[1].text == "Draft survives Clear Canvas and Undo" && !hasInlineEditor(),"Undo of Clear Canvas restores the screenshot, prior annotation and complete text draft")
        m.redo()
        require(m.image == nil && m.annotations.isEmpty && !hasInlineEditor() && m.tool == .arrow,"Redo of Clear Canvas returns to the empty workspace without an orphan editor")
        require(m.lineWidth == 20,"Clear Canvas and its Undo/Redo retain the saved20px drawing default")

        // Zoom shortcuts never collide with the unmodified numeric tool keys.
        resetDocument()
        key(24,"=",[.command]);require(m.zoom>0 && m.tool == .arrow,"Command-plus zooms in from Fit without changing the drawing tool")
        key(18,"1",[.command]);require(m.zoom == 1 && m.tool == .arrow,"Command1 selects native100% without selecting another tool")
        key(27,"-",[.control]);require(abs(m.zoom-1/1.2)<0.00001,"Control-minus provides the same zoom-out shortcut")
        key(24,"+",[.control,.shift]);require(abs(m.zoom-1)<0.00001,"Control-plus zooms in with either plus-key representation")
        key(29,"0",[.control]);require(m.zoom == 0 && !m.zoomInteracting,"Control0 returns to Fit and ends interactive zoom")
        key(18,"1");require(m.tool == .select && m.zoom == 0,"Unmodified1 still selects the Select tool")
        _ = startText("Text is retained when zoom starts")
        key(24,"=",[.command])
        require(!hasInlineEditor() && m.annotations.count == 1 && m.annotations[0].text == "Text is retained when zoom starts","A zoom command saves and closes active inline text exactly once")
        v.finishCanvasZoom()
        let zoomText=m.annotations
        NotificationCenter.default.post(name:.snapDriveZoomRequest,object:m,userInfo:["command":"actual"])
        require(m.zoom == 1 && m.annotations == zoomText,"Global zoom requests reach the canvas without changing annotations")
        v.finishCanvasZoom()

        // A large Retina fixture has room to pan, so cursor anchoring can be
        // verified without the unavoidable clamp at a document edge.
        do{
            let largeContext=CGContext(data:nil,width:3840,height:2160,bitsPerComponent:8,bytesPerRow:3840*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            largeContext.setFillColor(NSColor.white.cgColor);largeContext.fill(CGRect(x:0,y:0,width:3840,height:2160))
            let large=ImageEngine.bitmapImage(cgImage:largeContext.makeImage()!,logicalSize:CGSize(width:1920,height:1080))
            m.load(large);m.style.padding=0;m.style.shadow=0;m.style.radius=0
            await waitForCurrentPreview(m);host.reload()
            require(max(ImageEngine.pixelSize(m.preview!).width,ImageEngine.pixelSize(m.preview!).height)<=1800,"Fit starts with a bounded large-image preview")
            v.setCanvasZoom(1.5);await waitForCurrentPreview(m);host.reload()
            let visible=host.contentView.bounds
            let anchor=CGPoint(x:visible.minX+visible.width*0.43,y:visible.minY+visible.height*0.39)
            let windowAnchor=v.convert(anchor,to:nil),beforeAnchor=EditorInteraction.normalized(anchor,in:v.sourceFrame,clamp:false)
            let renderCount=m.previewRenderCount,sourceSize=ImageEngine.pixelSize(m.image!),annotationsBeforeZoom=m.annotations
            for _ in 0..<20{
                v.magnify(with:InteractionZoomEvent(location:windowAnchor,magnification:0.005,phase:.changed))
            }
            let afterAnchor=EditorInteraction.normalized(v.convert(windowAnchor,from:nil),in:v.sourceFrame,clamp:false)
            require(abs(beforeAnchor.x-afterAnchor.x)<0.0001 && abs(beforeAnchor.y-afterAnchor.y)<0.0001,"Trackpad pinch keeps the same screenshot pixel under the cursor")
            require(abs(m.zoom-1.5*pow(1.005,20))<0.00001 && m.zoomInteracting,"Native pinch events apply a continuous relative zoom")
            require(m.previewRenderCount == renderCount && max(ImageEngine.pixelSize(m.preview!).width,ImageEngine.pixelSize(m.preview!).height)<=1800,"Twenty pinch deltas reuse one bounded preview rather than rendering native4K every time")
            require(ImageEngine.pixelSize(m.image!) == sourceSize && m.annotations == annotationsBeforeZoom,"Zoom leaves native screenshot pixels and annotations unchanged")
            v.magnify(with:InteractionZoomEvent(location:windowAnchor,magnification:0,phase:.ended))
            await waitForCurrentPreview(m)
            require(!m.zoomInteracting && ImageEngine.pixelSize(m.preview!) == CGSize(width:3840,height:2160),"Ending a pinch restores native-resolution preview detail once")
            let beforeWheel=m.zoom,oldWheelPoint=EditorInteraction.normalized(v.convert(windowAnchor,from:nil),in:v.sourceFrame,clamp:false)
            host.scrollWheel(with:InteractionZoomEvent(location:windowAnchor,scroll:2,modifiers:.command,precise:false,phase:.changed))
            let afterWheel=EditorInteraction.normalized(v.convert(windowAnchor,from:nil),in:v.sourceFrame,clamp:false)
            require(m.zoom>beforeWheel && abs(oldWheelPoint.x-afterWheel.x)<0.0001 && abs(oldWheelPoint.y-afterWheel.y)<0.0001,"Command-mouse-wheel zooms at the cursor without moving its screenshot point")
            let commandWheelZoom=m.zoom
            host.scrollWheel(with:InteractionZoomEvent(location:windowAnchor,scroll:-2,modifiers:.control,precise:false,phase:.changed))
            require(m.zoom<commandWheelZoom,"Control-mouse-wheel also zooms out")
            let plainWheelZoom=m.zoom
            require(!v.handleZoomScroll(InteractionZoomEvent(location:windowAnchor,scroll:10,modifiers:[],precise:true,phase:.changed)) && m.zoom == plainWheelZoom,"An ordinary scroll is left to native panning and never changes zoom")
            try? await Task.sleep(nanoseconds:220_000_000);await waitForCurrentPreview(m)
            require(!m.zoomInteracting,"A settled mouse-wheel burst ends interactive preview rendering automatically")
            v.zoomBy(1e9);require(m.zoom == 4,"Zoom-in clamps at400%")
            v.zoomBy(1e-9);require(m.zoom == 0.1,"Zoom-out clamps at10%")
            v.setCanvasZoom(.nan);require(m.zoom == 0.1,"Non-finite zoom requests cannot corrupt canvas geometry")
            v.zoomCommand("fit");await waitForCurrentPreview(m);host.reload()
            require(m.zoom == 0 && !m.zoomInteracting && max(ImageEngine.pixelSize(m.preview!).width,ImageEngine.pixelSize(m.preview!).height)<=1800,"Fit after gestures returns to a bounded preview")
        }
        resetDocument();await waitForCurrentPreview(m);host.reload()

        // A missing or outdated preview must never start an edit against remembered geometry.
        resetDocument()
        require(m.previewIsCurrent, "Small fixture begins with a current preview")
        m.preview = nil
        m.tool = .text; mouse(.leftMouseDown, point(0.3,0.3)); mouse(.leftMouseUp, point(0.3,0.3))
        require(!hasInlineEditor() && m.annotations.isEmpty && m.undoStack.isEmpty, "Missing preview cannot start inline text using old geometry")
        require(m.status.contains("Updating preview"), "A blocked gesture explains that the preview is updating")
        draw(.rectangle, point(0.2,0.2), point(0.6,0.6))
        require(m.annotations.isEmpty && m.undoStack.isEmpty, "Missing preview cannot leave a shape draft or annotation")
        m.refresh(); host.reload()
        require(m.previewIsCurrent, "Refreshing a small fixture restores a current preview")
        _ = startText("Editing works again")
        v.commitInlineText()
        require(m.annotations.count == 1 && m.annotations[0].text == "Editing works again", "A current preview permits editing again")

        resetDocument()
        m.style.exportScale = 2
        require(!m.previewIsCurrent && m.preview != nil, "Larger preview fixture keeps its old preview while rendering the new revision")
        m.tool = .text; mouse(.leftMouseDown, point(0.3,0.3)); mouse(.leftMouseUp, point(0.3,0.3))
        require(!hasInlineEditor() && m.annotations.isEmpty, "An outdated preview cannot start a text draft")
        draw(.rectangle, point(0.2,0.2), point(0.6,0.6))
        require(m.annotations.isEmpty && m.undoStack.isEmpty, "Pending preview cannot draw using the old frame")
        await waitForCurrentPreview(m); host.reload()
        draw(.rectangle, point(0.2,0.2), point(0.6,0.6))
        require(m.annotations.count == 1 && abs(m.annotations[0].start.x - 0.2) < 0.0001, "New current preview allows a correctly positioned shape")
        await waitForCurrentPreview(m)
        m.style.exportScale = 1; await waitForCurrentPreview(m)

        resetDocument()
        _ = startText("Keep this pending draft")
        m.preview = nil
        mouse(.leftMouseDown, point(0.8,0.8)); mouse(.leftMouseUp, point(0.8,0.8))
        require(m.annotations.count == 1 && m.annotations[0].text == "Keep this pending draft" && !hasInlineEditor(), "Closing existing inline text still saves it when preview is missing")

        // Feedback must correspond to the link actually copied; unverified links are never claimed ready.
        let driveURL = URL(string: "https://drive.google.com/file/d/test-file/view?resourcekey=0-test-key")!
        let copied = DriveUploadResult(fileID: "test-file", driveURL: driveURL, isPublic: true, requestedSharing: .anyoneWithLink)
        let copiesBeforeLink = clipboard.count
        m.copyUploadLink(copied)
        require(clipboard.count == copiesBeforeLink + 1 && clipboard.last == driveURL.absoluteString, "Copy link preserves complete resource-key URL")
        require(m.status.contains("copied") && m.status.contains("Anyone"), "Copy-link status confirms actual action and access")
        require(m.toast == "Drive link copied", "Successful link copy shows a clear toast")
        let existingAccess = DriveUploadResult(fileID: "restricted-file", driveURL: driveURL, isPublic: false)
        m.copyUploadLink(existingAccess)
        require(m.status.contains("Existing Drive access") && !m.status.contains("Anyone"), "Copying a restricted link never claims public visibility")
        let unverified = DriveUploadResult(fileID: "test-file", driveURL: driveURL, warning: "Viewer link not yet available", hasVerifiedDriveURL: false)
        let copiesBeforeInvalid = clipboard.count
        m.copyUploadLink(unverified)
        require(clipboard.count == copiesBeforeInvalid, "Unverified links do not alter clipboard")
        window.contentView=nil
        print("PASS \(passed) native interaction checks: drawing/custom widths, magnifier placement/move/resize/zoom, precise selection, delete, drag undo, inline commit/focus/tool/export, cancel, selected-text clipboard, crop undo, copy-link feedback")
    }

    @MainActor static func waitForCurrentPreview(_ model: EditorModel) async {
        for _ in 0..<3000 {
            if model.previewIsCurrent { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        require(model.previewIsCurrent, "Preview fixture finishes its current revision")
    }

    @MainActor static func nextUIEventTurn() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor static func waitForRecognition(_ model: EditorModel) async {
        for _ in 0..<2000 {
            if !model.recognizing { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        require(!model.recognizing, "Text recognition fixture completes")
    }
}

/// Native event receiver tests use a private NSEvent subclass, never global events.
final class InteractionZoomEvent:NSEvent{
    let point:CGPoint,zoomDelta:CGFloat,scrollDelta:CGFloat,flags:NSEvent.ModifierFlags,eventPhase:NSEvent.Phase,precise:Bool
    init(location:CGPoint,magnification:CGFloat=0,scroll:CGFloat=0,modifiers:NSEvent.ModifierFlags=[],precise:Bool=true,phase:NSEvent.Phase){
        point=location;zoomDelta=magnification;scrollDelta=scroll;flags=modifiers;eventPhase=phase;self.precise=precise;super.init()
    }
    required init?(coder:NSCoder){fatalError("Event fixture does not decode")}
    override var locationInWindow:CGPoint{point}
    override var magnification:CGFloat{zoomDelta}
    override var scrollingDeltaY:CGFloat{scrollDelta}
    override var modifierFlags:NSEvent.ModifierFlags{flags}
    override var hasPreciseScrollingDeltas:Bool{precise}
    override var phase:NSEvent.Phase{eventPhase}
}

final class InteractionRecognitionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSizes: [CGSize] = []
    private var lines = [
        RecognizedLine(text: "Selected fixture text", rect: CGRect(x:0.1,y:0.2,width:0.5,height:0.15)),
        RecognizedLine(text: "Second fixture line", rect: CGRect(x:0.1,y:0.5,width:0.6,height:0.15))
    ]
    var sizes: [CGSize] { lock.lock(); defer { lock.unlock() }; return recordedSizes }
    func setLines(_ value: [RecognizedLine]) { lock.lock(); lines = value; lock.unlock() }
    func recognize(_ image: NSImage) -> [RecognizedLine] {
        lock.lock(); defer { lock.unlock() }
        recordedSizes.append(ImageEngine.pixelSize(image))
        return lines
    }
}
