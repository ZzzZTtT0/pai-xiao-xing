import Cocoa

enum PetMood: Int, CaseIterable {
    case idle=0, right=1, left=2, wave=3, jump=4, sad=5, sleepy=6, work=7, think=8
    var frames: Int { [6,8,8,4,5,8,6,6,6][rawValue] }
    var title: String { ["发呆","向右小跑","向左小跑","打招呼","跳一下","委屈","犯困","认真忙碌","托腮思考"][rawValue] }
}

final class PetArtwork {
    let frames: [[NSImage]]
    init(resourceURL: URL) throws {
        let url=resourceURL.appendingPathComponent("spritesheet.png")
        guard let atlas=NSImage(contentsOf:url),let cg=atlas.cgImage(forProposedRect:nil,context:nil,hints:nil),cg.width==1536,cg.height==1872 else {
            throw NSError(domain:"派小星",code:1,userInfo:[NSLocalizedDescriptionKey:"找不到有效的角色图集"])
        }
        frames=try (0..<9).map { row in
            try (0..<PetMood(rawValue:row)!.frames).map { col in
                guard let crop=cg.cropping(to:CGRect(x:col*192,y:row*208,width:192,height:208)) else { throw NSError(domain:"派小星",code:2) }
                return NSImage(cgImage:crop,size:NSSize(width:192,height:208))
            }
        }
    }

    func render(in bounds: CGRect, edge: DockEdge?, mood: PetMood, phase: Double, reduced: Bool) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect:bounds).addClip()
        let transform=NSAffineTransform()
        transform.translateX(by:bounds.minX,yBy:bounds.minY)
        transform.scaleX(by:bounds.width/192,yBy:bounds.height/208)
        transform.concat()
        let tick=Int(phase/0.14)
        let image=frames[mood.rawValue][reduced ? 0 : tick % mood.frames]
        guard let edge=edge else {
            image.draw(in:CGRect(x:0,y:0,width:192,height:208))
            return
        }
        let bob: CGFloat = reduced ? 0 : CGFloat(sin(phase*1.5))*0.8
        let bounce: CGFloat = mood == .jump && !reduced ? abs(CGFloat(sin(phase*5)))*7 : 0
        switch edge {
        case .left,.right:
            if edge == .right {
                let mirror=NSAffineTransform();mirror.translateX(by:192,yBy:0);mirror.scaleX(by:-1,yBy:1);mirror.concat()
            }
            let tilt=NSAffineTransform()
            tilt.translateX(by:25,yBy:90);tilt.rotate(byDegrees:reduced ? -5 : -5+CGFloat(sin(phase))*1.2);tilt.translateX(by:-25,yBy:-90);tilt.concat()
            let edgeMood: PetMood = mood == .idle ? .think : mood
            let face=frames[edgeMood.rawValue][reduced ? 0 : tick % edgeMood.frames]
            face.draw(in:CGRect(x:-66,y:bob+bounce,width:192,height:208))
            palm(CGRect(x:1,y:81+bob,width:24,height:21),vertical:true)
        case .top,.bottom:
            if edge == .top {
                let flip=NSAffineTransform();flip.translateX(by:0,yBy:208);flip.scaleX(by:1,yBy:-1);flip.concat()
            }
            let face=frames[mood.rawValue][reduced ? 0 : tick % mood.frames]
            face.draw(in:CGRect(x:0,y:-94+bob+bounce,width:192,height:208))
            palm(CGRect(x:47,y:1,width:30,height:21),vertical:false)
            palm(CGRect(x:116,y:1,width:30,height:21),vertical:false)
        }
    }

    private func palm(_ rect: CGRect, vertical: Bool) {
        let p=NSBezierPath(roundedRect:rect,xRadius:rect.width*0.48,yRadius:rect.height*0.48)
        NSColor(calibratedRed:0.97,green:0.66,blue:0.72,alpha:1).setFill();p.fill()
        NSColor(calibratedWhite:0.08,alpha:1).setStroke();p.lineWidth=2.2;p.stroke()
        let detail=NSBezierPath()
        if vertical {
            detail.move(to:CGPoint(x:rect.midX,y:rect.midY-4));detail.line(to:CGPoint(x:rect.midX+7,y:rect.midY-4))
        } else {
            detail.move(to:CGPoint(x:rect.midX-4,y:rect.minY+4));detail.line(to:CGPoint(x:rect.midX-4,y:rect.minY+9))
            detail.move(to:CGPoint(x:rect.midX+3,y:rect.minY+4));detail.line(to:CGPoint(x:rect.midX+3,y:rect.minY+9))
        }
        detail.lineWidth=1.5;detail.lineCapStyle = .round;detail.stroke()
    }
}

final class PetView: NSView {
    let artwork: PetArtwork
    weak var controller: PetController?
    var edge: DockEdge?
    var mood: PetMood = .idle
    var phase: Double=0
    var reduced=false
    init(frame: CGRect, artwork: PetArtwork) { self.artwork=artwork;super.init(frame:frame);setAccessibilityElement(true);setAccessibilityRole(.image);setAccessibilityLabel("派小星桌面宠物，双击跳跃，右键打开菜单") }
    required init?(coder:NSCoder) { fatalError() }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect:NSRect) { artwork.render(in:bounds,edge:edge,mood:mood,phase:phase,reduced:reduced) }
    override func mouseDown(with event:NSEvent) { controller?.beginDrag(event) }
    override func mouseDragged(with event:NSEvent) { controller?.drag(event) }
    override func mouseUp(with event:NSEvent) { controller?.endDrag(event) }
    override func rightMouseDown(with event:NSEvent) { controller?.showMenu(event,in:self) }
    func containsPet(_ point:CGPoint) -> Bool {
        let x=point.x/bounds.width*192,y=point.y/bounds.height*208
        switch edge {
        case .left: return CGRect(x:0,y:13,width:105,height:185).contains(CGPoint(x:x,y:y))
        case .right: return CGRect(x:87,y:13,width:105,height:185).contains(CGPoint(x:x,y:y))
        case .bottom: return CGRect(x:31,y:0,width:133,height:109).contains(CGPoint(x:x,y:y))
        case .top: return CGRect(x:31,y:99,width:133,height:109).contains(CGPoint(x:x,y:y))
        case nil: return CGRect(x:27,y:12,width:140,height:185).contains(CGPoint(x:x,y:y))
        }
    }
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class StatsView: NSView {
    var snapshot: UsageSnapshot?
    var session: SessionInfo?
    var message: String?
    var following=false
    override var isFlipped: Bool { true }
    private let ink=NSColor(calibratedRed:0.97,green:0.95,blue:0.98,alpha:1)
    private let muted=NSColor(calibratedRed:0.73,green:0.69,blue:0.76,alpha:1)
    private let pink=NSColor(calibratedRed:0.97,green:0.69,blue:0.76,alpha:1)
    private let mint=NSColor(calibratedRed:0.69,green:0.89,blue:0.80,alpha:1)

    func update(snapshot:UsageSnapshot?,session:SessionInfo?,message:String?,following:Bool) {
        self.snapshot=snapshot;self.session=session;self.message=message;self.following=following
        needsDisplay=true
        setAccessibilityElement(true);setAccessibilityRole(.group)
        setAccessibilityLabel("派小星会话状态，上下文已用\(TextFormat.tokens(snapshot?.contextUsed))，上限\(TextFormat.tokens(snapshot?.capacity))，上下文剩余\(TextFormat.tokens(snapshot?.contextRemaining))，短期额度剩余\(TextFormat.percent(snapshot?.primary?.remaining()))，每周额度剩余\(TextFormat.percent(snapshot?.secondary?.remaining()))。\(message ?? "")")
    }
    private func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat=12,_ color:NSColor?=nil,_ weight:NSFont.Weight = .regular,_ width:CGFloat=306,mono:Bool=false) {
        let p=NSMutableParagraphStyle();p.lineBreakMode = .byTruncatingTail
        let f=mono ? NSFont.monospacedDigitSystemFont(ofSize:size,weight:weight) : NSFont.systemFont(ofSize:size,weight:weight)
        (s as NSString).draw(in:CGRect(x:x,y:y,width:width,height:ceil(size*1.7)),withAttributes:[.font:f,.foregroundColor:color ?? ink,.paragraphStyle:p])
    }
    private func bar(_ rect:CGRect,_ fraction:Double?,_ color:NSColor) {
        NSColor.white.withAlphaComponent(0.10).setFill();NSBezierPath(roundedRect:rect,xRadius:3,yRadius:3).fill()
        if let value=fraction, value>0 { color.setFill();NSBezierPath(roundedRect:CGRect(x:rect.minX,y:rect.minY,width:rect.width*CGFloat(max(0,min(1,value))),height:rect.height),xRadius:3,yRadius:3).fill() }
    }
    override func draw(_ dirtyRect:NSRect) {
        let bg=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:19,yRadius:19)
        NSColor(calibratedRed:0.16,green:0.14,blue:0.20,alpha:0.97).setFill();bg.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke();bg.lineWidth=1;bg.stroke()
        text("派小星",18,15,17,pink,.semibold)
        text("会话状态",89,20,11,muted)
        let label=(following ? "跟随最近活跃 · " : "绑定 · ")+(session?.label ?? "尚未选择会话")
        text(label,18,47,11,muted)
        guard let s=snapshot else {
            text("还没有可显示的用量",18,91,17,ink,.medium)
            let p=NSMutableParagraphStyle();p.lineBreakMode = .byWordWrapping
            ((message ?? "完成一轮 Codex 对话后，悬停这里查看。") as NSString).draw(in:CGRect(x:18,y:129,width:305,height:85),withAttributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:muted,.paragraphStyle:p])
            text("右键派小星，可以重新选择会话。",18,244,12,muted)
            text("仅在本机读取日志，不上传会话数据",18,301,10,muted)
            return
        }
        text("上下文",18,79,12,muted)
        text(TextFormat.percent(s.contextFraction.map{$0*100})+" 已用",252,78,12,pink,.medium,76,mono:true)
        text("\(TextFormat.tokens(s.contextUsed)) / \(TextFormat.tokens(s.capacity))",18,100,20,ink,.semibold,300,mono:true)
        bar(CGRect(x:18,y:132,width:306,height:6),s.contextFraction,pink)
        text("剩余 \(TextFormat.tokens(s.contextRemaining)) tokens",18,147,11,muted)
        NSColor.white.withAlphaComponent(0.1).setFill();NSBezierPath(rect:CGRect(x:18,y:175,width:306,height:1)).fill()
        for (index,window) in [s.primary,s.secondary].enumerated() {
            let x:CGFloat=index==0 ? 18 : 180
            let remain=window?.remaining()
            text(window?.title ?? (index==0 ? "短期额度" : "每周额度"),x,188,11,muted,.regular,145)
            text(remain==nil ? "待更新" : TextFormat.percent(remain)+" 剩余",x,207,22,remain == nil ? muted : mint,.semibold,145,mono:true)
            bar(CGRect(x:x,y:239,width:144,height:4),remain.map{$0/100},mint)
            text(TextFormat.reset(window),x,250,9,muted,.regular,145)
        }
        text("上下文："+TextFormat.age(s.usageDate),18,279,10,muted)
        text("额度快照："+TextFormat.age(s.quotaDate),18,295,10,muted)
        text("账号额度为共享快照 · 右键切换会话",18,315,10,muted)
    }
}
