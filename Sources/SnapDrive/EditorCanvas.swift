import SwiftUI
import AppKit
import Combine

struct EditorCanvas: View {
    @EnvironmentObject var model: EditorModel
    var body: some View {
        NativeEditorCanvas(model:model)
            .overlay(alignment:.bottom) {
                if model.tool == .crop, let image = model.image, let rect = model.cropSelection {
                    cropControls(size:ImageEngine.pixelSize(image),rect:rect).padding(10)
                } else {
                    Text(hint).font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,12).padding(.vertical,5).background(.black.opacity(0.35),in:Capsule()).padding(.bottom,8).allowsHitTesting(false)
                }
            }
    }
    private func cropControls(size:CGSize,rect:CGRect)->some View {
        HStack(spacing:9) {
            VStack(alignment:.leading,spacing:2) {
                Text("Crop frame").font(.system(size:11,weight:.semibold))
                Text("\(Int((size.width*rect.width).rounded())) × \(Int((size.height*rect.height).rounded())) px").font(.system(size:10)).foregroundStyle(.secondary)
            }.fixedSize()
            Divider().frame(height:24)
            ForEach(CropEdge.insets,id:\.self) { edge in
                VStack(alignment:.leading,spacing:2) {
                    Text(edge.label).font(.system(size:9)).foregroundStyle(.secondary)
                    TextField(edge.label,value:Binding(get:{model.cropInset(edge)},set:{model.setCropInset(edge,value:$0)}),format:.number.grouping(.never).precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder).font(.system(size:11,design:.monospaced)).frame(width:48)
                        .accessibilityLabel(edge.label+" crop inset in pixels")
                }
            }
            Button("Cancel") {model.cancelCropSelection()}.controlSize(.small)
            Button("Apply crop") {model.applyCropSelection()}.buttonStyle(.borderedProminent).controlSize(.small)
        }.padding(9).background(.regularMaterial,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(.white.opacity(0.1)))
            .shadow(color:.black.opacity(0.23),radius:9,y:4)
    }
    private var hint:String {
        switch model.tool {
        case .hand:return "Drag to pan · You can also hold Space with any tool"
        case .select:return "Click to select · Drag to move · Drag handles to resize · Delete to remove · Double-click text to edit"
        case .text:return "Click to type · Return saves · Option-Return adds a line · Escape cancels"
        case .crop:return "Draw a crop frame · Adjust the edges · Return applies · Escape cancels"
        case .textselect:return "Drag over text to recognize and copy it"
        case .magnifier:return "Click to place a magnifier · Drag to choose its size · Adjust zoom in the sidebar"
        case .arrow:return "Drag to draw arrows · Hold Shift for straight angles · Draw again to add more · 1 selects · Delete removes the last arrow"
        default:return "Drag on the image to add \(model.tool.title.lowercased()) · Escape cancels"
        }
    }
}

private struct NativeEditorCanvas:NSViewRepresentable {
    @ObservedObject var model:EditorModel
    func makeNSView(context:Context)->EditorCanvasScrollView { EditorCanvasScrollView(model:model) }
    func updateNSView(_ view:EditorCanvasScrollView,context:Context){view.reload()}
}

/// A native document view owns mouse and keyboard events; scrolling never competes with annotation gestures.
@MainActor final class EditorCanvasScrollView:NSScrollView {
    let canvas:EditorCanvasDocumentView
    init(model:EditorModel){
        canvas=EditorCanvasDocumentView(model:model)
        super.init(frame:.zero)
        hasHorizontalScroller=true;hasVerticalScroller=true;autohidesScrollers=true
        borderType = .noBorder;drawsBackground=true;backgroundColor=NSColor(white:0.10,alpha:1)
        documentView=canvas;canvas.scrollHost=self
        setAccessibilityLabel("Screenshot editing canvas")
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is not supported")}
    override func layout(){super.layout();canvas.updateGeometry(viewport:contentView.bounds.size)}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();reload()}
    func reload(){canvas.reload();canvas.updateGeometry(viewport:contentView.bounds.size)}
    override func magnify(with event:NSEvent){if !canvas.handleMagnification(event){super.magnify(with:event)}}
    override func scrollWheel(with event:NSEvent){if !canvas.handleZoomScroll(event){super.scrollWheel(with:event)}}
}

@MainActor final class EditorCanvasDocumentView:NSView {
    let model:EditorModel
    weak var scrollHost:EditorCanvasScrollView?
    private var changes:AnyCancellable?
    private var focusObserver:NSObjectProtocol?
    private var commitObserver:NSObjectProtocol?
    private var zoomObserver:NSObjectProtocol?
    private var zoomSettlement:Task<Void,Never>?
    private var reloadScheduled=false
    private var suppressEditingClick=false
    private var spaceHeld=false
    private var cropDrag:(edge:CropEdge,start:CGPoint,rect:CGRect)?
    private var panStart:(pointer:CGPoint,origin:CGPoint)?
    private var panKeyMonitor:Any?
    private var keyWindowObserver:NSObjectProtocol?
    private var lastCursorTool:EditorTool?
    private var drawingStart:CGPoint?
    private var drawingEnd:CGPoint?
    private var drawingTool:EditorTool?
    private var originalAnnotation:Annotation?
    private var dragStart:CGPoint?
    private var activeHandle:AnnotationHandle?
    private var grabOffset=CGPoint.zero
    private var inlineEditor:CanvasInlineTextView?
    private var inlineID:UUID?
    private var inlinePoint=CGPoint.zero
    private var inlineHistoryID:UUID?
    private weak var inlineSource:NSImage?
    private var inlineScale:CGFloat=1
    private var lastHistoryID:UUID?
    private(set) var outputFrame=CGRect.zero
    private(set) var sourceFrame=CGRect.zero
    private(set) var factor:CGFloat=1
    private var sourcePixels:CGSize {model.image.map(ImageEngine.pixelSize) ?? CGSize(width:1,height:1)}
    override var isFlipped:Bool{true}
    override var acceptsFirstResponder:Bool{true}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool{true}

    init(model:EditorModel){
        self.model=model;super.init(frame:.zero)
        setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("Screenshot canvas");setAccessibilityIdentifier("screenshot.canvas")
        changes=model.objectWillChange.sink{[weak self] _ in
            guard let self,!self.reloadScheduled else{return};self.reloadScheduled=true
            DispatchQueue.main.async{[weak self] in self?.reloadScheduled=false;self?.reload();self?.scrollHost?.needsLayout=true}
        }
        focusObserver=NotificationCenter.default.addObserver(forName:.snapDriveFocusCanvas,object:nil,queue:.main){[weak self] _ in
            MainActor.assumeIsolated { guard let self else{return};self.commitInlineText();self.window?.makeFirstResponder(self) }
        }
        commitObserver=NotificationCenter.default.addObserver(forName:.snapDriveCommitText,object:nil,queue:.main){[weak self] notification in
            MainActor.assumeIsolated {
                guard let self,let sender=notification.object as? EditorModel,sender === self.model else{return}
                self.commitInlineText()
            }
        }
        zoomObserver=NotificationCenter.default.addObserver(forName:.snapDriveZoomRequest,object:nil,queue:.main){[weak self] notification in
            MainActor.assumeIsolated {
                guard let self,let sender=notification.object as? EditorModel,sender === self.model else{return}
                if let command=notification.userInfo?["command"] as? String{self.zoomCommand(command)}
                else if let value=notification.userInfo?["value"] as? Double{self.setCanvasZoom(value)}
                else if let factor=notification.userInfo?["factor"] as? Double{self.zoomBy(factor)}
            }
        }
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is not supported")}
    deinit{if let panKeyMonitor{NSEvent.removeMonitor(panKeyMonitor)};if let keyWindowObserver{NotificationCenter.default.removeObserver(keyWindowObserver)};zoomSettlement?.cancel();if let focusObserver{NotificationCenter.default.removeObserver(focusObserver)};if let commitObserver{NotificationCenter.default.removeObserver(commitObserver)};if let zoomObserver{NotificationCenter.default.removeObserver(zoomObserver)}}
    override func viewDidMoveToWindow(){
        super.viewDidMoveToWindow()
        if let panKeyMonitor { NSEvent.removeMonitor(panKeyMonitor);self.panKeyMonitor=nil }
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver);self.keyWindowObserver=nil }
        spaceHeld=false;panStart=nil
        guard let window else{return}
        panKeyMonitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp]){[weak self] event in
            guard event.keyCode==49 else{return event}
            let released=event.type == .keyUp
            let plain=event.modifierFlags.intersection([.command,.control,.option]).isEmpty
            let windowNumber=event.windowNumber
            let consumed=MainActor.assumeIsolated {
                guard let self,let window=self.window,window.windowNumber==windowNumber else{return false}
                if released && self.spaceHeld{self.setSpaceHeld(false);return true}
                guard !released,plain,self.inlineEditor==nil,!(window.firstResponder is NSTextView),
                      let clip=self.scrollHost?.contentView,
                      window.firstResponder===self || clip.bounds.contains(clip.convert(window.mouseLocationOutsideOfEventStream,from:nil)) else{return false}
                self.setSpaceHeld(true);return true
            }
            return consumed ? nil:event
        }
        keyWindowObserver=NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:window,queue:.main){[weak self] _ in
            MainActor.assumeIsolated{self?.panStart=nil;self?.setSpaceHeld(false)}
        }
    }
    func reload(){
        if lastCursorTool != model.tool {lastCursorTool=model.tool;window?.invalidateCursorRects(for:self)}
        let selected = model.selectedID.flatMap { id in model.annotations.first(where: { $0.id == id }) }
        let selection = selected.map { "Selected " + $0.kind.rawValue + ($0.kind == .text ? ": " + String($0.text.prefix(80)) : "") } ?? "No selection"
        setAccessibilityValue("\(model.annotations.count) annotations. \(selection)")
        if inlineEditor != nil && (inlineHistoryID != model.currentHistoryID || inlineSource !== model.image){cancelInlineText()}
        if lastHistoryID != model.currentHistoryID {panStart=nil;setSpaceHeld(false);clearDrag();zoomSettlement?.cancel();model.endZoomInteraction();lastHistoryID=model.currentHistoryID}
        needsDisplay=true
    }
    func updateGeometry(viewport:CGSize){
        guard model.preview != nil,let image=model.image else{frame.size=CGSize(width:max(1,viewport.width),height:max(1,viewport.height));outputFrame = .zero;sourceFrame = .zero;needsDisplay=true;return}
        let pixels=ImageEngine.dimensions(image:image,style:model.style)
        let fit=max(0.01,min(max(1,viewport.width-76)/max(1,pixels.width),max(1,viewport.height-76)/max(1,pixels.height)))
        factor=model.zoom==0 ? fit : model.zoom/max(1,window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
        let display=CGSize(width:pixels.width*factor,height:pixels.height*factor)
        let doc=CGSize(width:max(viewport.width,display.width+76),height:max(viewport.height,display.height+76))
        if frame.size != doc{frame.size=doc}
        outputFrame=CGRect(x:(doc.width-display.width)/2,y:(doc.height-display.height)/2,width:display.width,height:display.height)
        let source=ImageEngine.sourceFrame(image:image,style:model.style)
        sourceFrame=CGRect(x:outputFrame.minX+source.minX*factor,y:outputFrame.minY+source.minY*factor,width:source.width*factor,height:source.height*factor)
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect){
        NSColor(white:0.10,alpha:1).setFill();dirtyRect.fill()
        guard let preview=model.preview,outputFrame.width>0 else{
            let text=model.previewRendering ? "Preparing preview…":"This export could not be rendered. Reduce the output size."
            text.draw(at:CGPoint(x:30,y:40),withAttributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.secondaryLabelColor]);return
        }
        if model.style.background=="transparent"{drawCheckerboard(outputFrame,dirty:dirtyRect)}
        preview.draw(in:outputFrame,from:CGRect(origin:.zero,size:preview.size),operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSNumber(value:factor>=1 ? NSImageInterpolation.none.rawValue:NSImageInterpolation.high.rawValue)])
        if let id=model.selectedID,let a=model.annotations.first(where:{$0.id==id}),inlineID != id{
            let rect=EditorInteraction.bounds(a,frame:sourceFrame,pixels:sourcePixels).insetBy(dx:-2,dy:-2)
            let path=NSBezierPath(rect:rect);path.lineWidth=1;path.setLineDash([4,3],count:2,phase:0);NSColor.controlAccentColor.setStroke();path.stroke()
            for (_,p) in EditorInteraction.handles(a,frame:sourceFrame,pixels:sourcePixels){let h=NSBezierPath(ovalIn:CGRect(x:p.x-4,y:p.y-4,width:8,height:8));NSColor.white.setFill();h.fill();NSColor.controlAccentColor.setStroke();h.lineWidth=1.5;h.stroke()}
        }
        if model.tool == .crop {
            if drawingTool == .crop,let a=drawingStart,let b=drawingEnd {drawCropFrame(CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y)))}
            else if let rect=model.cropSelection {drawCropFrame(displayCrop(rect))}
        } else if let a=drawingStart,let b=drawingEnd,let tool=drawingTool{drawDraft(from:a,to:b,tool:tool)}
    }
    private func displayCrop(_ rect:CGRect)->CGRect {
        CGRect(x:sourceFrame.minX+rect.minX*sourceFrame.width,y:sourceFrame.minY+rect.minY*sourceFrame.height,width:rect.width*sourceFrame.width,height:rect.height*sourceFrame.height)
    }
    private func drawCropFrame(_ rect:CGRect){
        guard rect.width>0,rect.height>0,let context=NSGraphicsContext.current?.cgContext else{return}
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.47).cgColor)
        context.addRect(sourceFrame);context.addRect(rect);context.drawPath(using:.eoFill)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor);context.setLineWidth(1)
        for value:CGFloat in [1/3,2/3] {
            let x=rect.minX+rect.width*value,y=rect.minY+rect.height*value
            context.move(to:CGPoint(x:x,y:rect.minY));context.addLine(to:CGPoint(x:x,y:rect.maxY))
            context.move(to:CGPoint(x:rect.minX,y:y));context.addLine(to:CGPoint(x:rect.maxX,y:y))
        }
        context.strokePath()
        NSColor.controlAccentColor.setStroke();let outline=NSBezierPath(rect:rect);outline.lineWidth=2;outline.stroke()
        NSColor.white.setFill()
        for (_,point) in EditorInteraction.cropHandles(in:rect) {
            let dot=NSBezierPath(roundedRect:CGRect(x:point.x-4,y:point.y-4,width:8,height:8),xRadius:2,yRadius:2)
            dot.fill();dot.lineWidth=1.5;dot.stroke()
        }
        context.restoreGState()
    }
    private func drawCheckerboard(_ rect:CGRect,dirty:CGRect){
        let visible=rect.intersection(visibleRect).intersection(dirty)
        guard !visible.isNull,!visible.isEmpty else{return}
        NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:rect).addClip()
        NSColor(white:0.23,alpha:1).setFill();rect.fill()
        let minX=Int(floor(visible.minX/12)),maxX=Int(ceil(visible.maxX/12)),minY=Int(floor(visible.minY/12)),maxY=Int(ceil(visible.maxY/12))
        NSColor(white:0.29,alpha:1).setFill()
        if maxX>=minX && maxY>=minY {for x in minX...maxX{for y in minY...maxY where (x+y)%2==0{CGRect(x:x*12,y:y*12,width:12,height:12).fill()}}}
        NSGraphicsContext.restoreGraphicsState()
    }
    private func drawDraft(from a:CGPoint,to b:CGPoint,tool:EditorTool){
        if tool == .arrow {
            guard let context=NSGraphicsContext.current?.cgContext else{return}
            let scale=sourceFrame.width/max(1,sourcePixels.width)
            context.saveGState();context.clip(to:sourceFrame)
            ImageEngine.drawArrow(from:a,to:b,lineWidth:model.lineWidth*scale,minimumHeadLength:10*scale,color:NSColor(model.ink).cgColor,context:context)
            context.restoreGState()
            return
        }
        var r=CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y))
        if tool == .magnifier {
            let circle=EditorInteraction.circle(from:EditorInteraction.normalized(a,in:sourceFrame),to:EditorInteraction.normalized(b,in:sourceFrame),pixels:sourcePixels)
            r=CGRect(x:sourceFrame.minX+circle.minX*sourceFrame.width,y:sourceFrame.minY+circle.minY*sourceFrame.height,width:circle.width*sourceFrame.width,height:circle.height*sourceFrame.height)
        }
        let path:NSBezierPath
        path=tool == .ellipse || tool == .magnifier ? NSBezierPath(ovalIn:r):NSBezierPath(rect:r)
        let color=tool == .crop || tool == .textselect ? NSColor.white:NSColor(model.ink)
        if [.redact,.pixelate,.blur,.crop,.textselect].contains(tool){color.withAlphaComponent(0.18).setFill();path.fill()}
        color.setStroke();path.lineWidth=2;path.setLineDash([5,3],count:2,phase:0);path.stroke()
    }
    private var canvasCursor:NSCursor {
        if panStart != nil{return .closedHand}
        if spaceHeld || model.tool == .hand{return .openHand}
        return model.tool == .select ? .arrow:model.tool == .text ? .iBeam:.crosshair
    }
    override func resetCursorRects(){
        addCursorRect(bounds,cursor:canvasCursor)
        if model.tool == .crop,!spaceHeld,panStart==nil,let selection=model.cropSelection {
            let rect=displayCrop(selection)
            addCursorRect(rect,cursor:.openHand)
            for (edge,point) in EditorInteraction.cropHandles(in:rect) {
                addCursorRect(CGRect(x:point.x-8,y:point.y-8,width:16,height:16),cursor:edge.cursor)
            }
        }
    }
    private func setSpaceHeld(_ held:Bool){
        guard held != spaceHeld else{return}
        spaceHeld=held;window?.invalidateCursorRects(for:self)
    }
    override func resignFirstResponder()->Bool{
        setSpaceHeld(false)
        return super.resignFirstResponder()
    }
    override func keyUp(with event:NSEvent){
        if event.keyCode==49 && spaceHeld{setSpaceHeld(false)}else{super.keyUp(with:event)}
    }

    override func mouseDown(with event:NSEvent){
        let wasEditing=inlineEditor != nil || suppressEditingClick
        suppressEditingClick=false
        commitInlineText();window?.makeFirstResponder(self)
        let p=convert(event.locationInWindow,from:nil)
        clearDrag()
        if (spaceHeld || model.tool == .hand),let clip=scrollHost?.contentView {
            panStart=(event.locationInWindow,clip.bounds.origin)
            window?.invalidateCursorRects(for:self);NSCursor.closedHand.set();return
        }
        if wasEditing{model.selectAnnotation(nil);needsDisplay=true;return}
        guard model.previewIsCurrent else{model.status="Updating preview…";return}
        if model.tool == .crop {
            if let selection=model.cropSelection,let edge=EditorInteraction.cropEdge(at:p,in:displayCrop(selection)){
                cropDrag=(edge,EditorInteraction.normalized(p,in:sourceFrame,clamp:false),selection)
                return
            }
            if sourceFrame.contains(p){drawingStart=p;drawingEnd=p;drawingTool = .crop}
        } else if model.tool == .select {
            if let id=model.selectedID,let selected=model.annotations.first(where:{$0.id==id}),let handle=EditorInteraction.handle(at:p,annotation:selected,frame:sourceFrame,pixels:sourcePixels){
                originalAnnotation=selected;dragStart=p;activeHandle=handle.0;grabOffset=CGPoint(x:p.x-handle.1.x,y:p.y-handle.1.y);_ = model.beginAnnotationEdit(id:id)
            } else if let id=EditorInteraction.hitTest(p,annotations:model.annotations,frame:sourceFrame,pixels:sourcePixels),let selected=model.annotations.first(where:{$0.id==id}){
                model.selectAnnotation(id)
                if selected.kind == .text && event.clickCount>=2{beginInlineText(at:selected.start,replacing:selected);return}
                originalAnnotation=selected;dragStart=p;_ = model.beginAnnotationEdit(id:id)
            } else {model.selectAnnotation(nil)}
        } else if model.tool == .text {
            guard sourceFrame.contains(p) else{model.selectAnnotation(nil);return}
            if let id=EditorInteraction.hitTest(p,annotations:model.annotations,frame:sourceFrame,pixels:sourcePixels),let selected=model.annotations.first(where:{$0.id==id && $0.kind == .text}){model.selectAnnotation(id);beginInlineText(at:selected.start,replacing:selected)}
            else{model.selectAnnotation(nil);beginInlineText(at:EditorInteraction.normalized(p,in:sourceFrame),replacing:nil)}
        } else if sourceFrame.contains(p){model.selectAnnotation(nil);drawingStart=p;drawingEnd=p;drawingTool=model.tool}
        else{model.selectAnnotation(nil)}
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent){
        if let start=panStart,let host=scrollHost {
            let clip=host.contentView,point=event.locationInWindow
            let target=CGPoint(x:start.origin.x-(point.x-start.pointer.x),y:start.origin.y+(point.y-start.pointer.y))
            clip.scroll(to:clip.constrainBoundsRect(CGRect(origin:target,size:clip.bounds.size)).origin)
            host.reflectScrolledClipView(clip)
            return
        }
        autoscroll(with:event)
        let p=convert(event.locationInWindow,from:nil)
        if updateCropDrag(at:p) {return}
        if let original=originalAnnotation,let start=dragStart{
            let changed:Annotation
            if let activeHandle{let target=CGPoint(x:p.x-grabOffset.x,y:p.y-grabOffset.y);changed=EditorInteraction.resized(original,handle:activeHandle,to:EditorInteraction.normalized(target,in:sourceFrame),pixels:sourcePixels)}
            else{changed=EditorInteraction.moved(original,delta:CGPoint(x:(p.x-start.x)/max(1,sourceFrame.width),y:(p.y-start.y)/max(1,sourceFrame.height)),pixels:sourcePixels)}
            model.updateAnnotationEdit(changed)
        } else if drawingStart != nil{drawingEnd=drawingPoint(p,modifiers:event.modifierFlags)}
        needsDisplay=true
    }
    override func flagsChanged(with event:NSEvent){
        if drawingStart != nil,drawingTool == .arrow{drawingEnd=drawingPoint(convert(event.locationInWindow,from:nil),modifiers:event.modifierFlags);needsDisplay=true}
        else{super.flagsChanged(with:event)}
    }
    private func drawingPoint(_ point:CGPoint,modifiers:NSEvent.ModifierFlags)->CGPoint{
        if drawingTool == .arrow,modifiers.contains(.shift),let start=drawingStart{return EditorInteraction.constrainedArrowEnd(from:start,to:point,in:sourceFrame)}
        return EditorInteraction.point(EditorInteraction.normalized(point,in:sourceFrame),in:sourceFrame)
    }
    private func updateCropDrag(at point:CGPoint)->Bool {
        guard let drag=cropDrag else{return false}
        let target=EditorInteraction.normalized(point,in:sourceFrame,clamp:false)
        model.cropSelection=EditorInteraction.adjustCrop(drag.rect,edge:drag.edge,delta:CGPoint(x:target.x-drag.start.x,y:target.y-drag.start.y),pixels:sourcePixels)
        needsDisplay=true;return true
    }
    override func mouseUp(with event:NSEvent){
        if panStart != nil {panStart=nil;window?.invalidateCursorRects(for:self);canvasCursor.set();return}
        if updateCropDrag(at:convert(event.locationInWindow,from:nil)){cropDrag=nil;window?.invalidateCursorRects(for:self);return}
        if originalAnnotation != nil{model.finishAnnotationEdit();clearDrag();needsDisplay=true;return}
        defer{clearDrag();needsDisplay=true}
        guard let start=drawingStart,let tool=drawingTool else{return}
        let p=drawingPoint(convert(event.locationInWindow,from:nil),modifiers:event.modifierFlags),a=EditorInteraction.normalized(start,in:sourceFrame),b=EditorInteraction.normalized(p,in:sourceFrame)
        let rect=CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y))
        if tool == .crop || tool == .textselect{
            guard rect.width*sourceFrame.width>4,rect.height*sourceFrame.height>4 else{return}
            if tool == .crop{
                model.cropSelection=EditorInteraction.pixelCrop(rect,pixels:sourcePixels)
                window?.invalidateCursorRects(for:self)
            }else{model.recognize(copy:true,region:rect)};return
        }
        if tool == .magnifier {
            let circle: CGRect
            if hypot(p.x-start.x,p.y-start.y)<4 { circle=EditorInteraction.circle(center:a,diameter:model.magnifierDiameter,pixels:sourcePixels) }
            else { circle=EditorInteraction.circle(from:a,to:b,pixels:sourcePixels) }
            guard circle.width*sourcePixels.width>=8 else{return}
            model.add(Annotation(kind:.magnifier,start:circle.origin,end:CGPoint(x:circle.maxX,y:circle.maxY),colorHex:model.ink.hexString,lineWidth:model.lineWidth,magnification:model.magnification))
            model.tool = .select;model.status="Magnifier added. Drag to move, use corner handles to resize."
            return
        }
        guard let kind=tool.annotationKind,kind != .text else{return}
        if kind == .arrow{guard hypot((b.x-a.x)*sourceFrame.width,(b.y-a.y)*sourceFrame.height)>4 else{return}}
        else{guard rect.width*sourceFrame.width>3,rect.height*sourceFrame.height>3 else{return}}
        model.add(Annotation(kind:kind,start:a,end:b,text:"",colorHex:model.ink.hexString,lineWidth:model.lineWidth,fontSize:model.fontSize))
    }
    override func keyDown(with event:NSEvent){
        if !event.modifierFlags.intersection([.command,.control]).isEmpty,event.modifierFlags.intersection([.option]).isEmpty{
            switch event.charactersIgnoringModifiers?.lowercased(){
            case "=","+":zoomCommand("in");return
            case "-","_":zoomCommand("out");return
            case "0":zoomCommand("fit");return
            case "1":zoomCommand("actual");return
            default:break
            }
        }
        guard event.modifierFlags.intersection([.command,.control,.option]).isEmpty else{super.keyDown(with:event);return}
        switch event.keyCode{
        case 49:setSpaceHeld(true)
        case 36,76:
            if model.tool == .crop && model.cropSelection != nil{model.applyCropSelection()}
            else{super.keyDown(with:event)}
        case 51,117:model.removeSelected();needsDisplay=true
        case 53:
            if panStart != nil || spaceHeld {panStart=nil;setSpaceHeld(false);window?.invalidateCursorRects(for:self);return}
            if model.tool == .crop {
                clearDrag();model.cancelCropSelection();window?.invalidateCursorRects(for:self);needsDisplay=true;return
            }
            if originalAnnotation != nil{model.finishAnnotationEdit(cancelled:true)}
            clearDrag();model.selectAnnotation(nil);needsDisplay=true
        case 123,124,125,126:
            let amount:CGFloat=event.modifierFlags.contains(.shift) ? 10:1
            let dx:CGFloat=event.keyCode==123 ? -amount:event.keyCode==124 ? amount:0
            let dy:CGFloat=event.keyCode==126 ? -amount:event.keyCode==125 ? amount:0
            let delta=CGPoint(x:dx/max(1,sourcePixels.width),y:dy/max(1,sourcePixels.height))
            if model.tool == .crop,let rect=model.cropSelection {
                model.cropSelection=EditorInteraction.adjustCrop(rect,edge:.move,delta:delta,pixels:sourcePixels)
                window?.invalidateCursorRects(for:self)
            } else {model.nudgeSelected(delta:delta)}
            needsDisplay=true
        default:
            if let shortcut=event.charactersIgnoringModifiers,let tool=EditorTool.fromShortcut(shortcut){if tool != .select && tool != .hand{model.selectAnnotation(nil)};model.tool=tool;window?.invalidateCursorRects(for:self)}
            else if let n=Int(event.charactersIgnoringModifiers ?? ""),n>=0,n<=9{let index=n==0 ? 9:n-1;if EditorTool.allCases.indices.contains(index){model.tool=EditorTool.allCases[index];window?.invalidateCursorRects(for:self)}}
            else{super.keyDown(with:event)}
        }
    }
    override func magnify(with event:NSEvent){if !handleMagnification(event){super.magnify(with:event)}}
    override func scrollWheel(with event:NSEvent){if !handleZoomScroll(event){super.scrollWheel(with:event)}}
    @discardableResult func handleMagnification(_ event:NSEvent)->Bool{
        guard model.image != nil,model.preview != nil else{return false}
        let amount=Double(event.magnification)
        guard amount.isFinite else{return true}
        if abs(amount)>0.000001{zoomBy(max(0.05,1+amount),at:convert(event.locationInWindow,from:nil))}
        if event.phase.contains(.ended) || event.phase.contains(.cancelled){finishCanvasZoom()}
        return true
    }
    @discardableResult func handleZoomScroll(_ event:NSEvent)->Bool{
        guard !event.modifierFlags.intersection([.command,.control]).isEmpty,event.modifierFlags.intersection([.option]).isEmpty,model.image != nil,model.preview != nil else{return false}
        let delta=Double(event.scrollingDeltaY)
        guard delta.isFinite else{return true}
        if abs(delta)>0.000001{
            let sensitivity=event.hasPreciseScrollingDeltas ? 0.008:0.08
            zoomBy(exp(min(4,max(-4,delta*sensitivity))),at:convert(event.locationInWindow,from:nil))
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled){finishCanvasZoom()}
        return true
    }
    func zoomCommand(_ command:String){
        switch command{
        case "in":zoomBy(1.2)
        case "out":zoomBy(1/1.2)
        case "fit":setCanvasZoom(0);finishCanvasZoom()
        case "actual":setCanvasZoom(1)
        default:break
        }
    }
    func zoomBy(_ multiplier:Double,at anchor:CGPoint?=nil){
        guard multiplier.isFinite,multiplier>0 else{return}
        let backing=max(1,window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
        let current=model.zoom == 0 ? Double(factor*backing):model.zoom
        setCanvasZoom(min(4,max(0.1,current*multiplier)),at:anchor)
    }
    /// Zoom uses the existing bitmap during the gesture; only settled zoom asks
    /// the model for native detail. The same screenshot point stays under the cursor.
    func setCanvasZoom(_ requested:Double,at anchor:CGPoint?=nil){
        guard requested.isFinite,let host=scrollHost,model.image != nil,model.preview != nil,outputFrame.width>0 else{return}
        let value=requested == 0 ? 0:min(4,max(0.1,requested))
        let clip=host.contentView,visible=clip.bounds
        let point=anchor ?? CGPoint(x:visible.midX,y:visible.midY)
        let normalized=EditorInteraction.normalized(point,in:outputFrame,clamp:false)
        let offset=CGPoint(x:point.x-visible.minX,y:point.y-visible.minY)
        if !model.zoomInteracting{
            commitInlineText()
            if originalAnnotation != nil{model.finishAnnotationEdit()}
            clearDrag();model.beginZoomInteraction()
        }
        model.zoom=value
        updateGeometry(viewport:clip.bounds.size);host.layoutSubtreeIfNeeded();updateGeometry(viewport:clip.bounds.size)
        let relocated=EditorInteraction.point(normalized,in:outputFrame)
        let proposed=CGRect(origin:CGPoint(x:relocated.x-offset.x,y:relocated.y-offset.y),size:clip.bounds.size)
        clip.scroll(to:clip.constrainBoundsRect(proposed).origin);host.reflectScrolledClipView(clip)
        needsDisplay=true
        zoomSettlement?.cancel()
        zoomSettlement=Task{[weak self] in
            try? await Task.sleep(nanoseconds:180_000_000)
            guard !Task.isCancelled else{return}
            self?.finishCanvasZoom()
        }
    }
    func finishCanvasZoom(){zoomSettlement?.cancel();zoomSettlement=nil;model.endZoomInteraction()}
    private func clearDrag(){cropDrag=nil;drawingStart=nil;drawingEnd=nil;drawingTool=nil;originalAnnotation=nil;dragStart=nil;activeHandle=nil;grabOffset = .zero}

    func beginInlineText(at point:CGPoint,replacing annotation:Annotation?){
        commitInlineText();clearDrag()
        inlineID=annotation?.id;inlinePoint=point;inlineHistoryID=model.currentHistoryID;inlineSource=model.image
        let editor=CanvasInlineTextView(frame:.zero)
        inlineScale=max(0.01,sourceFrame.width/max(1,sourcePixels.width))
        editor.font=NSFont.systemFont(ofSize:max(1,(annotation?.fontSize ?? model.fontSize)*inlineScale),weight:.semibold)
        editor.textColor=annotation.map{NSColor(hex:$0.colorHex)} ?? NSColor(model.ink)
        editor.backgroundColor=NSColor(white:0.12,alpha:0.98);editor.drawsBackground=true;editor.isRichText=false
        editor.isEditable=true;editor.isSelectable=true;editor.allowsUndo=true;editor.textContainerInset=CGSize(width:6,height:6)
        editor.isVerticallyResizable=true;editor.isHorizontallyResizable=false
        editor.wantsLayer=true;editor.layer?.cornerRadius=6;editor.layer?.borderWidth=1.5;editor.layer?.borderColor=NSColor.controlAccentColor.cgColor
        let location=EditorInteraction.point(point,in:sourceFrame)
        let oldWidth=annotation.map{EditorInteraction.bounds($0,frame:sourceFrame,pixels:sourcePixels).width+16} ?? 220
        let width=min(max(100,oldWidth),max(100,bounds.maxX-location.x-10))
        editor.frame=CGRect(x:location.x-6,y:location.y-6,width:width,height:max(44,(editor.font?.pointSize ?? 20)*1.8+12))
        editor.textContainer?.containerSize=CGSize(width:width-12,height:CGFloat.greatestFiniteMagnitude);editor.textContainer?.widthTracksTextView=true
        editor.string=annotation?.text ?? ""
        editor.setAccessibilityLabel(annotation == nil ? "New screenshot text":"Edit screenshot text")
        editor.onCommit={[weak self] in self?.commitInlineText()};editor.onCancel={[weak self] in self?.cancelInlineText()}
        editor.onFocusLoss={[weak self] in
            guard let self else{return}
            self.suppressEditingClick=true
            self.commitInlineText(restoreFocus:false)
            DispatchQueue.main.async{[weak self] in self?.suppressEditingClick=false}
        }
        editor.onChange={[weak self] in self?.resizeInlineEditor()}
        inlineEditor=editor;addSubview(editor);window?.makeFirstResponder(editor)
        if annotation != nil{editor.selectAll(nil)}
        model.status="Type your label. Return saves; Option-Return adds a line; Escape cancels."
        needsDisplay=true
    }
    private func resizeInlineEditor(){
        guard let editor=inlineEditor,let container=editor.textContainer,let manager=editor.layoutManager else{return}
        manager.ensureLayout(for:container)
        editor.frame.size.height=min(220,max(44,manager.usedRect(for:container).height+16));editor.needsDisplay=true
    }
    func commitInlineText(restoreFocus:Bool=true,finishTool:Bool=true){
        guard let editor=inlineEditor else{return}
        let text=editor.string,id=inlineID,point=inlinePoint
        inlineEditor=nil;inlineID=nil;editor.ending=true;editor.removeFromSuperview()
        if inlineHistoryID==model.currentHistoryID,inlineSource === model.image{_ = model.commitText(text,at:point,replacing:id)}
        if finishTool && model.tool == .text{model.tool = .select}
        if restoreFocus{window?.makeFirstResponder(self)};needsDisplay=true
    }
    func cancelInlineText(){
        guard let editor=inlineEditor else{return}
        inlineEditor=nil;inlineID=nil;editor.ending=true;editor.removeFromSuperview();if model.tool == .text{model.tool = .select};window?.makeFirstResponder(self);needsDisplay=true
    }
}

@MainActor private final class CanvasInlineTextView:NSTextView {
    var onCommit:(()->Void)?
    var onCancel:(()->Void)?
    var onChange:(()->Void)?
    var onFocusLoss:(()->Void)?
    var ending=false
    override func keyDown(with event:NSEvent){
        if event.keyCode==53{onCancel?();return}
        if event.keyCode==36 || event.keyCode==76{if event.modifierFlags.contains(.option){insertText("\n",replacementRange:selectedRange())}else{onCommit?()};return}
        super.keyDown(with:event)
    }
    override func didChangeText(){super.didChangeText();onChange?();needsDisplay=true}
    override func resignFirstResponder()->Bool{
        let result=super.resignFirstResponder()
        if result && !ending{onFocusLoss?()}
        return result
    }
    override func draw(_ dirtyRect:NSRect){
        super.draw(dirtyRect)
        if string.isEmpty{"Type text…".draw(at:CGPoint(x:7,y:7),withAttributes:[.font:font ?? NSFont.systemFont(ofSize:16),.foregroundColor:NSColor.secondaryLabelColor])}
    }
}

extension NSColor {
    convenience init(hex:String){
        var string=hex.trimmingCharacters(in:CharacterSet.alphanumerics.inverted)
        if string.count==3{string=string.map{"\($0)\($0)"}.joined()}
        let number=UInt64(string,radix:16) ?? 0x7371FC
        self.init(srgbRed:CGFloat((number>>16)&255)/255,green:CGFloat((number>>8)&255)/255,blue:CGFloat(number&255)/255,alpha:1)
    }
}
