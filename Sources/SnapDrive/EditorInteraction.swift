import AppKit
import Foundation

extension Notification.Name {
    static let snapDriveCommitText = Notification.Name("SnapDrive.commitText")
    static let snapDriveFocusCanvas = Notification.Name("SnapDrive.focusCanvas")
    static let snapDriveZoomRequest = Notification.Name("SnapDrive.zoomRequest")
}

enum AnnotationHandle: Equatable {
    case start, end, topLeft, topRight, bottomLeft, bottomRight
}

/// Shared by native mouse events and deterministic geometry checks. Coordinates use the source image's top left.
enum EditorInteraction {
    static func point(_ normalized: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + normalized.x * frame.width, y: frame.minY + normalized.y * frame.height)
    }
    static func normalized(_ point: CGPoint, in frame: CGRect, clamp: Bool = true) -> CGPoint {
        let p = CGPoint(x: (point.x-frame.minX)/max(0.0001,frame.width), y: (point.y-frame.minY)/max(0.0001,frame.height))
        return clamp ? CGPoint(x: bounded(p.x),y: bounded(p.y)) : p
    }
    static func normalizedBounds(_ a: Annotation, pixels: CGSize) -> CGRect {
        if a.kind == .magnifier { return ImageEngine.magnifierBounds(a, pixels:pixels) }
        if a.kind == .text {
            let size = (a.text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: max(8,a.fontSize),weight: .semibold)])
            return CGRect(x:a.start.x,y:a.start.y,width:max(2,size.width)/max(1,pixels.width),height:max(a.fontSize,size.height)/max(1,pixels.height))
        }
        return CGRect(x:min(a.start.x,a.end.x),y:min(a.start.y,a.end.y),width:abs(a.end.x-a.start.x),height:abs(a.end.y-a.start.y))
    }
    static func bounds(_ a: Annotation, frame: CGRect, pixels: CGSize) -> CGRect {
        let r = normalizedBounds(a,pixels:pixels)
        return CGRect(x:frame.minX+r.minX*frame.width,y:frame.minY+r.minY*frame.height,width:r.width*frame.width,height:r.height*frame.height)
    }
    static func handles(_ a: Annotation, frame: CGRect, pixels: CGSize) -> [(AnnotationHandle,CGPoint)] {
        guard a.kind != .text else { return [] }
        if a.kind == .arrow { return [(.start,point(a.start,in:frame)),(.end,point(a.end,in:frame))] }
        let r = bounds(a,frame:frame,pixels:pixels)
        return [(.topLeft,CGPoint(x:r.minX,y:r.minY)),(.topRight,CGPoint(x:r.maxX,y:r.minY)),(.bottomLeft,CGPoint(x:r.minX,y:r.maxY)),(.bottomRight,CGPoint(x:r.maxX,y:r.maxY))]
    }
    static func handle(at p: CGPoint, annotation: Annotation, frame: CGRect, pixels: CGSize, radius: CGFloat = 9) -> (AnnotationHandle,CGPoint)? {
        handles(annotation,frame:frame,pixels:pixels).min(by:{ distance($0.1,p)<distance($1.1,p) }).flatMap { distance($0.1,p)<=radius ? $0 : nil }
    }
    static func hitTest(_ p: CGPoint, annotations: [Annotation], frame: CGRect, pixels: CGSize, tolerance: CGFloat = 7) -> UUID? {
        // The renderer draws solid redactions last; selection follows the same visual stacking order.
        let stack = annotations.filter{$0.kind != .redact && $0.kind != .magnifier} + annotations.filter{$0.kind == .magnifier} + annotations.filter{$0.kind == .redact}
        return stack.reversed().first(where:{ contains(p,annotation:$0,frame:frame,pixels:pixels,tolerance:tolerance) })?.id
    }
    static func contains(_ p: CGPoint, annotation a: Annotation, frame: CGRect, pixels: CGSize, tolerance: CGFloat = 7) -> Bool {
        let r = bounds(a,frame:frame,pixels:pixels)
        let line = max(tolerance,a.lineWidth*frame.width/max(1,pixels.width)/2+3)
        switch a.kind {
        case .magnifier: return ellipseContains(p, rect:r.insetBy(dx:-3,dy:-3))
        case .text,.redact,.pixelate,.blur: return r.insetBy(dx:-3,dy:-3).contains(p)
        case .rectangle:
            return r.insetBy(dx:-line,dy:-line).contains(p) && !r.insetBy(dx:line,dy:line).contains(p)
        case .ellipse:
            guard r.width > 0.1,r.height > 0.1 else { return r.insetBy(dx:-line,dy:-line).contains(p) }
            let outer = CGRect(x:r.minX-line,y:r.minY-line,width:r.width+line*2,height:r.height+line*2)
            let inner = r.insetBy(dx:line,dy:line)
            return ellipseContains(p,rect:outer) && (inner.width<=0 || inner.height<=0 || !ellipseContains(p,rect:inner))
        case .arrow:
            let start=point(a.start,in:frame),end=point(a.end,in:frame)
            let scale=frame.width/max(1,pixels.width)
            guard let geometry=ImageEngine.arrowGeometry(from:start,to:end,lineWidth:a.lineWidth*scale,minimumHeadLength:10*scale) else{return false}
            if segmentDistance(p,geometry.start,geometry.shaftEnd)<=max(tolerance,geometry.width/2+3){return true}
            return geometry.head.contains(p) || geometry.head.copy(strokingWithWidth:tolerance*2,lineCap:.round,lineJoin:.round,miterLimit:2).contains(p)
        }
    }
    static func moved(_ original: Annotation, delta: CGPoint, pixels: CGSize) -> Annotation {
        let r=normalizedBounds(original,pixels:pixels)
        let x=min(max(0,1-min(1,r.width)),max(0,r.minX+delta.x))-r.minX
        let y=min(max(0,1-min(1,r.height)),max(0,r.minY+delta.y))-r.minY
        var result=original
        result.start=CGPoint(x:bounded(original.start.x+x),y:bounded(original.start.y+y))
        result.end=CGPoint(x:bounded(original.end.x+x),y:bounded(original.end.y+y))
        return result
    }
    static func resized(_ original: Annotation, handle: AnnotationHandle, to point: CGPoint, pixels: CGSize = CGSize(width:1,height:1)) -> Annotation {
        let p=CGPoint(x:bounded(point.x),y:bounded(point.y))
        var result=original
        if handle == .start { result.start=p;return result }
        if handle == .end { result.end=p;return result }
        let r=CGRect(x:min(original.start.x,original.end.x),y:min(original.start.y,original.end.y),width:abs(original.end.x-original.start.x),height:abs(original.end.y-original.start.y))
        let anchor: CGPoint
        switch handle {
        case .topLeft: anchor=CGPoint(x:r.maxX,y:r.maxY)
        case .topRight: anchor=CGPoint(x:r.minX,y:r.maxY)
        case .bottomLeft: anchor=CGPoint(x:r.maxX,y:r.minY)
        case .bottomRight: anchor=CGPoint(x:r.minX,y:r.minY)
        default: return result
        }
        if original.kind == .magnifier {
            let circle = circle(from:anchor,to:p,pixels:pixels)
            result.start = circle.origin; result.end = CGPoint(x:circle.maxX,y:circle.maxY)
            return result
        }
        result.start=CGPoint(x:min(anchor.x,p.x),y:min(anchor.y,p.y))
        result.end=CGPoint(x:max(anchor.x,p.x),y:max(anchor.y,p.y))
        return result
    }
    /// Rectangles are normalized, but circles must be square in native pixels.
    static func circle(from anchor: CGPoint, to point: CGPoint, pixels: CGSize) -> CGRect {
        let width = max(1,pixels.width), height = max(1,pixels.height)
        let a = CGPoint(x:bounded(anchor.x)*width,y:bounded(anchor.y)*height)
        let p = CGPoint(x:bounded(point.x)*width,y:bounded(point.y)*height)
        let right = p.x >= a.x, down = p.y >= a.y
        let availableX = right ? width-a.x:a.x, availableY = down ? height-a.y:a.y
        let diameter = max(0,min(max(abs(p.x-a.x),abs(p.y-a.y)),availableX,availableY))
        return CGRect(x:(right ? a.x:a.x-diameter)/width,y:(down ? a.y:a.y-diameter)/height,width:diameter/width,height:diameter/height)
    }
    static func circle(center: CGPoint, diameter: CGFloat, pixels: CGSize) -> CGRect {
        let width = max(1,pixels.width), height = max(1,pixels.height)
        let d = max(1,min(diameter,width,height))
        let x = min(width-d,max(0,center.x*width-d/2)), y = min(height-d,max(0,center.y*height-d/2))
        return CGRect(x:x/width,y:y/height,width:d/width,height:d/height)
    }
    static func segmentDistance(_ p:CGPoint,_ a:CGPoint,_ b:CGPoint)->CGFloat {
        let dx=b.x-a.x,dy=b.y-a.y,length=dx*dx+dy*dy
        if length<0.00001{return distance(p,a)}
        let t=min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/length))
        return distance(p,CGPoint(x:a.x+t*dx,y:a.y+t*dy))
    }
    /// Snap in displayed/native pixel geometry, then stop at the screenshot edge.
    static func constrainedArrowEnd(from start:CGPoint,to point:CGPoint,in frame:CGRect)->CGPoint {
        guard frame.width>0,frame.height>0,[start.x,start.y,point.x,point.y].allSatisfy({$0.isFinite}) else{return start}
        let dx=point.x-start.x,dy=point.y-start.y,length=hypot(dx,dy)
        guard length>0.001 else{return start}
        let increment=CGFloat.pi/4,angle=(atan2(dy,dx)/increment).rounded()*increment
        let x=cos(angle),y=sin(angle)
        var distance=length
        if x>0.00001{distance=min(distance,(frame.maxX-start.x)/x)}else if x < -0.00001{distance=min(distance,(frame.minX-start.x)/x)}
        if y>0.00001{distance=min(distance,(frame.maxY-start.y)/y)}else if y < -0.00001{distance=min(distance,(frame.minY-start.y)/y)}
        return CGPoint(x:start.x+x*max(0,distance),y:start.y+y*max(0,distance))
    }
    static func distance(_ a:CGPoint,_ b:CGPoint)->CGFloat{hypot(a.x-b.x,a.y-b.y)}
    private static func ellipseContains(_ p:CGPoint,rect:CGRect)->Bool {
        guard rect.width>0,rect.height>0 else{return false}
        let x=(p.x-rect.midX)/(rect.width/2),y=(p.y-rect.midY)/(rect.height/2)
        return x*x+y*y<=1
    }
    private static func bounded(_ v:CGFloat)->CGFloat{min(1,max(0,v))}
}
