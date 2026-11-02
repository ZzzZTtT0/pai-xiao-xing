import Cocoa

func renderBitmap(size:CGSize,draw:()->Void) -> NSBitmapImageRep {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    NSGraphicsContext.current?.cgContext.clear(CGRect(origin:.zero,size:size))
    draw();NSGraphicsContext.restoreGraphicsState()
    return rep
}

func renderActivityPreview(_ artwork:PetArtwork,to folder:URL) throws {
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    var session=SessionInfo(id:"example-session",path:URL(fileURLWithPath:"/fixture/session.jsonl"),folder:"示例项目",modified:Date())
    session.sourceName="Cockpit 示例"
    let card=StatsView(frame:CGRect(x:0,y:0,width:344,height:342))
    card.update(snapshot:UsageSnapshot(inputTokens:120_000,outputTokens:2000,capacity:475_000,usageDate:Date(),primary:LimitWindow(usedPercent:25,minutes:300,resetsAt:Date().addingTimeInterval(3600)),secondary:LimitWindow(usedPercent:40,minutes:10080,resetsAt:Date().addingTimeInterval(86400)),quotaDate:Date()),session:session,message:nil,following:true)
    let bubble=ActivityBubbleView(frame:CGRect(x:0,y:0,width:238,height:84))
    let layout=ActivityBubbleLayout(frame:bubble.frame,tailAtTop:false,tailX:119)
    bubble.update(operation:"运行测试",source:session.sourceName,layout:layout)
    func cached(_ view:NSView) -> NSImage? {
        guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return nil }
        view.cacheDisplay(in:view.bounds,to:rep)
        guard let image=rep.cgImage else { return nil }
        return NSImage(cgImage:image,size:view.bounds.size)
    }
    let rep=renderBitmap(size:CGSize(width:1000,height:600)) {
        NSColor(calibratedRed:0.94,green:0.95,blue:0.97,alpha:1).setFill();NSBezierPath(rect:CGRect(x:0,y:0,width:1000,height:600)).fill()
        ("派小星 v1.1" as NSString).draw(at:CGPoint(x:40,y:540),withAttributes:[.font:NSFont.systemFont(ofSize:30,weight:.semibold),.foregroundColor:NSColor(calibratedRed:0.24,green:0.18,blue:0.27,alpha:1)])
        ("Cockpit 多实例会话 · 任务操作气泡" as NSString).draw(at:CGPoint(x:42,y:506),withAttributes:[.font:NSFont.systemFont(ofSize:17),.foregroundColor:NSColor.darkGray])
        artwork.render(in:CGRect(x:126,y:96,width:192,height:208),edge:nil,mood:.work,phase:0.28,reduced:false)
        cached(bubble)?.draw(in:CGRect(x:103,y:310,width:238,height:84))
        cached(card)?.draw(in:CGRect(x:584,y:108,width:344,height:342))
        ("执行任务时，显示当前关键操作\n完成或取消后，气泡自动收起" as NSString).draw(in:CGRect(x:66,y:31,width:400,height:54),withAttributes:[.font:NSFont.systemFont(ofSize:15),.foregroundColor:NSColor.darkGray])
        ("用量和气泡跟随同一个会话\n右键可切换实例、锁定会话或关闭气泡" as NSString).draw(in:CGRect(x:553,y:31,width:410,height:54),withAttributes:[.font:NSFont.systemFont(ofSize:15),.foregroundColor:NSColor.darkGray])
        ("界面示例，非真实会话数据" as NSString).draw(at:CGPoint(x:695,y:471),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.gray])
    }
    try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("activity-preview.png"))
    print("Rendered synthetic activity bubble and Cockpit usage preview")
}
func renderPreviews(_ artwork:PetArtwork,to folder:URL) throws {
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let size=CGSize(width:384,height:416)
    for edge in DockEdge.allCases {
        let rep=renderBitmap(size:size) { artwork.render(in:CGRect(origin:.zero,size:size),edge:edge,mood:.idle,phase:0,reduced:true) }
        guard let png=rep.representation(using:.png,properties:[:]) else { throw NSError(domain:"preview",code:1) }
        try png.write(to:folder.appendingPathComponent("\(edge.rawValue).png"))
    }
    let labels:[(DockEdge?,String)] = [(nil,"自由活动"),(.left,"左边 · 半身探头"),(.right,"右边 · 半身探头"),(.top,"顶边 · 倒挂托腮"),(.bottom,"底边 · 趴边托腮")]
    let rep=renderBitmap(size:CGSize(width:1000,height:640)) {
        NSColor(calibratedRed:0.93,green:0.95,blue:0.97,alpha:1).setFill();NSBezierPath(rect:CGRect(x:0,y:0,width:1000,height:640)).fill()
        ("派小星，搬到桌面上" as NSString).draw(at:CGPoint(x:32,y:584),withAttributes:[.font:NSFont.systemFont(ofSize:28,weight:.semibold),.foregroundColor:NSColor(calibratedRed:0.20,green:0.16,blue:0.25,alpha:1)])
        ("四边吸附 · 半身探头 · 双手托腮 · 悬停查看用量" as NSString).draw(at:CGPoint(x:34,y:550),withAttributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.darkGray])
        for (index,pair) in labels.enumerated() {
            let x:CGFloat=30+CGFloat(index%3)*232,y:CGFloat=index<3 ? 286 : 26
            let box=CGRect(x:x,y:y+28,width:204,height:210)
            NSColor.white.setFill();NSBezierPath(roundedRect:box,xRadius:15,yRadius:15).fill()
            // Screen boundary indicator exists in the preview only.
            if let e=pair.0 {
                let line=NSBezierPath()
                switch e {
                case .left:line.move(to:CGPoint(x:box.minX,y:box.minY));line.line(to:CGPoint(x:box.minX,y:box.maxY))
                case .right:line.move(to:CGPoint(x:box.maxX,y:box.minY));line.line(to:CGPoint(x:box.maxX,y:box.maxY))
                case .top:line.move(to:CGPoint(x:box.minX,y:box.maxY));line.line(to:CGPoint(x:box.maxX,y:box.maxY))
                case .bottom:line.move(to:CGPoint(x:box.minX,y:box.minY));line.line(to:CGPoint(x:box.maxX,y:box.minY))
                }
                NSColor(calibratedRed:0.67,green:0.57,blue:0.67,alpha:1).setStroke();line.lineWidth=3;line.stroke()
            }
            artwork.render(in:box,edge:pair.0,mood:.idle,phase:0,reduced:true)
            (pair.1 as NSString).draw(at:CGPoint(x:x+6,y:y+5),withAttributes:[.font:NSFont.systemFont(ofSize:14,weight:.medium),.foregroundColor:NSColor.darkGray])
        }
        ("透明桌面窗口\n靠近边缘松手，即可吸附\n双击跳跃，右键切换动作" as NSString).draw(in:CGRect(x:730,y:350,width:245,height:125),withAttributes:[.font:NSFont.systemFont(ofSize:17),.foregroundColor:NSColor.darkGray])
        ("状态面板读取本地用量\n显示上下文已用和剩余\n显示账号额度与更新时间" as NSString).draw(in:CGRect(x:730,y:130,width:245,height:125),withAttributes:[.font:NSFont.systemFont(ofSize:17),.foregroundColor:NSColor.darkGray])
    }
    try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("派小星-桌面效果预览.png"))
    let home=ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath:$0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    let reader=SessionReader(home:home)
    let config=Bundle.main.resourceURL.flatMap { try? Data(contentsOf:$0.appendingPathComponent("Defaults.json")) }.flatMap { (try? JSONSerialization.jsonObject(with:$0)) as? [String:Any] }
    let preferred=config?["preferredSessionID"] as? String
    let sessions=reader.sessions(preferredID:preferred)
    let session=sessions.first(where:{$0.id==preferred}) ?? sessions.first
    let data=session.map { reader.read($0) } ?? (nil,"尚无本地用量")
    let card=StatsView(frame:CGRect(x:0,y:0,width:344,height:342))
    card.update(snapshot:data.0,session:session,message:data.1,following:false)
    if let bitmap=card.bitmapImageRepForCachingDisplay(in:card.bounds) {
        card.cacheDisplay(in:card.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("派小星-真实用量面板.png"))
    }
    print("Rendered four transparent edge poses and overview to \(folder.path)")
}

func renderingTests(_ artwork:PetArtwork) throws {
    var count=0
    for edge in ([nil] as [DockEdge?])+DockEdge.allCases.map({Optional($0)}) {
        func pixels(_ mood:PetMood) -> Data {
            let rep=renderBitmap(size:CGSize(width:192,height:208)) { artwork.render(in:CGRect(x:0,y:0,width:192,height:208),edge:edge,mood:mood,phase:0.3,reduced:false) }
            return Data(bytes:rep.bitmapData!,count:rep.bytesPerRow*rep.pixelsHigh)
        }
        let idle=pixels(.idle)
        for mood in [PetMood.sad,.wave,.jump] {
            guard pixels(mood) != idle else { throw TestFailure.failed("docked action must visibly change: \(String(describing:edge)) \(mood)") }
            count+=1
        }
    }
    print("PASS: \(count) native pixel comparisons — expressions and jump visibly change in free and all four docked poses")
}

let args=CommandLine.arguments
do {
    if args.contains("--self-test") { try runTests();exit(0) }
    if args.contains("--inspect-sources") {
        let userHome=FileManager.default.homeDirectoryForCurrentUser
        let home=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CODEX_HOME"] ?? userHome.appendingPathComponent(".codex").path)
        let reader=SessionReader(home:home,cockpitRoot:userHome.appendingPathComponent(".cockpit_tools/instances/codex"),additionalHomes:[userHome.appendingPathComponent(".codex")])
        let sessions=reader.sessions(preferredID:nil)
        let rows=reader.sources().map { source -> [String:Any] in
            let matches=sessions.filter { $0.selectionKey.hasPrefix(source.home.path+"/") }
            let state=matches.first.map { reader.readState($0) }
            return ["source":source.label,"discoveredSessions":matches.count,"latestHasUsage":state?.usage != nil,"latestTaskActive":state?.activity.bubbleText() != nil]
        }
        let data=try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]);print(String(data:data,encoding:.utf8)!);exit(0)
    }
    if let index=args.firstIndex(of:"--inspect-log"),args.count>index+1 {
        let path=URL(fileURLWithPath:args[index+1]),reader=SessionReader(home:path.deletingLastPathComponent())
        let session=SessionInfo(id:"inspection",path:path,folder:"",modified:Date())
        let (s,error)=reader.read(session)
        var result:[String:Any]=["contextUsed":s?.contextUsed as Any,"capacity":s?.capacity as Any,"remaining":s?.contextRemaining as Any,"primaryRemaining":s?.primary?.remaining() as Any,"secondaryRemaining":s?.secondary?.remaining() as Any]
        if let error=error { result["message"]=error }
        result=result.mapValues { value in let mirror=Mirror(reflecting:value);if mirror.displayStyle == .optional { return mirror.children.first?.value ?? NSNull() };return value }
        let data=try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]);print(String(data:data,encoding:.utf8)!);exit(0)
    }
    let app=NSApplication.shared
    let resources=Bundle.main.resourceURL ?? URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
    let artwork=try PetArtwork(resourceURL:resources)
    if args.contains("--render-tests") { try renderingTests(artwork);exit(0) }
    if let index=args.firstIndex(of:"--render-previews"),args.count>index+1 { try renderPreviews(artwork,to:URL(fileURLWithPath:args[index+1]));exit(0) }
    if let index=args.firstIndex(of:"--render-activity-preview"),args.count>index+1 { try renderActivityPreview(artwork,to:URL(fileURLWithPath:args[index+1]));exit(0) }
    let smoke=args.contains("--smoke-test")
    if !smoke,let bundleID=Bundle.main.bundleIdentifier,
       NSRunningApplication.runningApplications(withBundleIdentifier:bundleID).contains(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}) {
        DistributedNotificationCenter.default().postNotificationName(PetController.showNotification,object:nil);exit(0)
    }
    let preferences=smoke ? UserDefaults(suiteName:"local.paixiaoxing.desktop.smoke")! : .standard
    let delegate=PetController(artwork:artwork,resourceURL:resources,preferences:preferences)
    delegate.smokeMode=smoke
    app.delegate=delegate
    app.run()
    if smoke { exit(delegate.smokePassed ? 0 : 1) }
} catch {
    fputs("派小星：\(error)\n",stderr)
    exit(1)
}
