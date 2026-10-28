import Cocoa

final class PetController: NSObject, NSApplicationDelegate {
    static let showNotification=Notification.Name("local.paixiaoxing.desktop.show")
    let artwork: PetArtwork
    let defaults: UserDefaults
    let reader: SessionReader
    let queue=DispatchQueue(label:"local.paixiaoxing.logs",qos:.utility)
    var window: PetPanel!
    var petView: PetView!
    var tooltip: PetPanel!
    var statsView: StatsView!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var dataTimer: Timer?
    var sessionList: [SessionInfo]=[]
    var currentSession: SessionInfo?
    var snapshot: UsageSnapshot?
    var dataMessage: String?
    var preferredID: String?
    var following=false
    var fetching=false
    var selectionGeneration=0
    var lastDiscovery=Date.distantPast
    var started=Date()
    var hoverStarted: Date?
    var outsideStarted: Date?
    var dragging=false
    var moved=false
    var dragMouse=CGPoint.zero
    var dragOrigin=CGPoint.zero
    var actionUntil=Date.distantPast
    var lastIdleChange=Date()
    var manuallyHidden=false
    var snapEnabled=true
    var interactionScale: CGFloat=192
    var dockedScreen: NSScreen?
    var smokeMode=false
    var smokePassed=false

    init(artwork:PetArtwork,resourceURL:URL,preferences:UserDefaults = .standard) {
        self.artwork=artwork
        self.defaults=preferences
        let env=ProcessInfo.processInfo.environment
        let home=URL(fileURLWithPath:env["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path,isDirectory:true)
        reader=SessionReader(home:home)
        super.init()
        let config=(try? Data(contentsOf:resourceURL.appendingPathComponent("Defaults.json"))).flatMap { (try? JSONSerialization.jsonObject(with:$0)) as? [String:Any] }
        preferredID=(defaults.string(forKey:"sessionID") ?? config?["preferredSessionID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        following=defaults.object(forKey:"followRecentSession") as? Bool ?? (preferredID == nil)
        snapEnabled=defaults.object(forKey:"snapEnabled") as? Bool ?? true
        interactionScale=CGFloat(defaults.double(forKey:"petWidth"));if interactionScale<120 || interactionScale>300 { interactionScale=192 }
    }

    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        let area=(NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let size=petSize(in:area)
        window=PetPanel(contentRect:CGRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        configure(window)
        window.title="派小星"
        window.setAccessibilityLabel("派小星桌面宠物")
        petView=PetView(frame:CGRect(origin:.zero,size:size),artwork:artwork);petView.controller=self
        window.contentView=petView
        let screen=restoredScreen()
        dockedScreen=screen
        var position=CGPoint(x:screen.visibleFrame.maxX-size.width-100,y:screen.visibleFrame.minY+160)
        if defaults.object(forKey:"positionX") != nil {
            position.x=screen.visibleFrame.minX+CGFloat(defaults.double(forKey:"positionX"))*max(0,screen.visibleFrame.width-size.width)
            position.y=screen.visibleFrame.minY+CGFloat(defaults.double(forKey:"positionY"))*max(0,screen.visibleFrame.height-size.height)
        }
        if let value=defaults.string(forKey:"dockEdge"),let edge=DockEdge(rawValue:value),snapEnabled {
            petView.edge=edge;position=Geometry.docked(position,size:size,area:screen.visibleFrame,edge:edge)
        }
        window.setFrameOrigin(Geometry.constrained(position,size:size,area:screen.visibleFrame))
        statsView=StatsView(frame:CGRect(x:0,y:0,width:344,height:342))
        tooltip=PetPanel(contentRect:statsView.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        configure(tooltip);tooltip.hasShadow=true;tooltip.ignoresMouseEvents=true;tooltip.contentView=statsView
        tooltip.title="派小星会话状态"
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image=NSImage(systemSymbolName:"star.fill",accessibilityDescription:"派小星")
        statusItem.button?.toolTip="派小星：拖动贴边，悬停查看用量"
        statusItem.button?.target=self;statusItem.button?.action=#selector(statusMenu)
        NotificationCenter.default.addObserver(self,selector:#selector(screensChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(showAgain),name:Self.showNotification,object:nil)
        window.orderFrontRegardless()
        timer=Timer.scheduledTimer(withTimeInterval:0.08,repeats:true) { [weak self] _ in self?.tick() }
        dataTimer=Timer.scheduledTimer(withTimeInterval:4,repeats:true) { [weak self] _ in self?.refreshData() }
        refreshData(force:true)
        if smokeMode { DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { self.runWindowSmokeTest() } }
    }

    func configure(_ panel:NSPanel) {
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false
        panel.level = .floating;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false;panel.isMovableByWindowBackground=false
        panel.animationBehavior = .none
    }
    var reduced: Bool { defaults.bool(forKey:"quietAnimations") || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func petSize(in area:CGRect) -> CGSize {
        let w=min(interactionScale,area.width,area.height*192/208)
        return CGSize(width:w,height:w*208/192)
    }
    func screen(at point:CGPoint) -> NSScreen {
        if let s=NSScreen.screens.first(where:{$0.frame.contains(point)}) { return s }
        return NSScreen.screens.min { a,b in hypot(a.frame.midX-point.x,a.frame.midY-point.y)<hypot(b.frame.midX-point.x,b.frame.midY-point.y) } ?? NSScreen.main!
    }
    func restoredScreen() -> NSScreen {
        let stored=defaults.integer(forKey:"screenNumber")
        return NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue == stored } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    func updatePosition(_ position:CGPoint,edge:DockEdge?,screen:NSScreen,animate:Bool) {
        let size=petSize(in:screen.visibleFrame)
        if window.frame.size != size { window.setContentSize(size);petView.frame=CGRect(origin:.zero,size:size) }
        petView.edge=edge;dockedScreen=screen
        let target=edge.map { Geometry.docked(position,size:size,area:screen.visibleFrame,edge:$0) } ?? Geometry.constrained(position,size:size,area:screen.visibleFrame)
        if animate && !reduced {
            NSAnimationContext.runAnimationGroup { context in context.duration=0.22;context.timingFunction=CAMediaTimingFunction(name:.easeOut);window.animator().setFrameOrigin(target) }
        } else { window.setFrameOrigin(target) }
        savePosition(target,in:screen,edge:edge)
        petView.needsDisplay=true
    }
    func savePosition(_ origin:CGPoint,in screen:NSScreen,edge:DockEdge?) {
        let area=screen.visibleFrame,size=window.frame.size
        defaults.set(Double(Geometry.clamp((origin.x-area.minX)/max(1,area.width-size.width),0,1)),forKey:"positionX")
        defaults.set(Double(Geometry.clamp((origin.y-area.minY)/max(1,area.height-size.height),0,1)),forKey:"positionY")
        defaults.set((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue,forKey:"screenNumber")
        defaults.set(edge?.rawValue,forKey:"dockEdge")
    }

    func beginDrag(_ event:NSEvent) {
        if event.clickCount>=2 { perform(.jump);return }
        dragging=true;moved=false;dragMouse=NSEvent.mouseLocation;dragOrigin=window.frame.origin
        tooltip.orderOut(nil);hoverStarted=nil;NSCursor.closedHand.set()
    }
    func drag(_ event:NSEvent) {
        guard dragging else { return }
        let mouse=NSEvent.mouseLocation,dx=mouse.x-dragMouse.x,dy=mouse.y-dragMouse.y
        if hypot(dx,dy)>4 { moved=true }
        guard moved else { return }
        petView.edge=nil
        let s=screen(at:mouse),size=petSize(in:s.visibleFrame)
        if window.frame.size != size { window.setContentSize(size);petView.frame=CGRect(origin:.zero,size:size) }
        let p=Geometry.constrained(CGPoint(x:dragOrigin.x+dx,y:dragOrigin.y+dy),size:size,area:s.visibleFrame)
        window.setFrameOrigin(p);dockedScreen=s
        petView.mood=dx>=0 ? .right : .left;petView.needsDisplay=true
    }
    func endDrag(_ event:NSEvent) {
        guard dragging else { return }
        dragging=false;NSCursor.arrow.set()
        if moved {
            let s=screen(at:NSEvent.mouseLocation)
            let edge=snapEnabled ? Geometry.nearbyEdge(origin:window.frame.origin,size:window.frame.size,area:s.visibleFrame) : nil
            updatePosition(window.frame.origin,edge:edge,screen:s,animate:true)
            petView.mood = .idle;actionUntil = .distantPast
        }
        moved=false
    }
    func perform(_ mood:PetMood) {
        petView.mood=mood;actionUntil=Date().addingTimeInterval(mood == .jump ? 2.4 : 5)
        lastIdleChange=Date();petView.phase=0;petView.needsDisplay=true
    }

    func tick() {
        guard window != nil else { return }
        let now=Date()
        petView.phase=now.timeIntervalSince(started);petView.reduced=reduced
        if !dragging && actionUntil != .distantPast && now>=actionUntil {
            petView.mood = .idle;actionUntil = .distantPast;lastIdleChange=now
        }
        if !dragging && actionUntil<now && now.timeIntervalSince(lastIdleChange)>14 {
            petView.mood=reduced ? .idle : [.idle,.idle,.sleepy,.think].randomElement()!
            lastIdleChange=now
        }
        if window.isVisible && !manuallyHidden { petView.needsDisplay=true }
        let mouse=NSEvent.mouseLocation
        let local=CGPoint(x:mouse.x-window.frame.minX,y:mouse.y-window.frame.minY)
        let overPet=window.isVisible && !manuallyHidden && petView.containsPet(local)
        if !dragging { window.ignoresMouseEvents = !overPet }
        let overCard=tooltip.isVisible && tooltip.frame.contains(mouse)
        if !dragging && (overPet || overCard) {
            outsideStarted=nil
            if hoverStarted==nil { hoverStarted=now }
            if now.timeIntervalSince(hoverStarted!)>=0.55 {
                let s=dockedScreen ?? screen(at:mouse)
                let target=Geometry.tooltip(pet:window.frame,size:tooltip.frame.size,area:s.visibleFrame)
                tooltip.setFrameOrigin(target);tooltip.orderFrontRegardless()
            }
        } else {
            hoverStarted=nil
            if outsideStarted==nil { outsideStarted=now }
            if dragging || now.timeIntervalSince(outsideStarted!)>0.25 { tooltip.orderOut(nil) }
        }
    }

    func refreshData(force:Bool=false) {
        guard !fetching else { return };fetching=true
        let generation=selectionGeneration,id=preferredID,auto=following
        let discover=force || Date().timeIntervalSince(lastDiscovery)>16
        let candidates=sessionList
        queue.async { [weak self] in
            guard let self=self else { return }
            let sessions=discover ? self.reader.sessions(preferredID:id) : candidates
            let chosen=auto ? sessions.first : sessions.first(where:{$0.id==id})
            let result=chosen.map { self.reader.read($0) } ?? (nil,auto ? "没有找到本地 Codex 主会话" : "没有找到绑定会话，右键派小星重新选择")
            DispatchQueue.main.async {
                self.fetching=false
                guard self.selectionGeneration==generation else { self.refreshData(force:true);return }
                self.sessionList=sessions;self.currentSession=chosen;self.snapshot=result.0;self.dataMessage=result.1
                if discover { self.lastDiscovery=Date() }
                self.statsView.update(snapshot:result.0,session:chosen,message:result.1,following:auto)
            }
        }
    }

    @objc func statusMenu() {
        let menu=makeMenu();statusItem.menu=menu;statusItem.button?.performClick(nil);statusItem.menu=nil
    }
    func showMenu(_ event:NSEvent,in view:NSView) {
        dragging=false;tooltip.orderOut(nil)
        NSMenu.popUpContextMenu(makeMenu(),with:event,for:view)
    }
    func item(_ title:String,_ selector:Selector,represented:Any?=nil,checked:Bool=false) -> NSMenuItem {
        let i=NSMenuItem(title:title,action:selector,keyEquivalent:"");i.target=self;i.representedObject=represented;i.state=checked ? .on : .off;return i
    }
    func makeMenu() -> NSMenu {
        let menu=NSMenu()
        let heading=NSMenuItem(title:"派小星",action:nil,keyEquivalent:"");heading.isEnabled=false;menu.addItem(heading)
        menu.addItem(item(manuallyHidden ? "显示派小星" : "暂时隐藏",#selector(toggleHidden)))
        menu.addItem(item("回到屏幕中央",#selector(centerPet)))
        menu.addItem(item("自动吸附屏幕边缘",#selector(toggleSnap),checked:snapEnabled))
        let edges=NSMenu(title:"贴边姿势")
        for edge in DockEdge.allCases { edges.addItem(item(edge.title,#selector(selectEdge(_:)),represented:edge.rawValue,checked:petView.edge==edge)) }
        let edgeItem=NSMenuItem(title:"贴边姿势",action:nil,keyEquivalent:"");edgeItem.submenu=edges;menu.addItem(edgeItem)
        let actions=NSMenu(title:"表情动作")
        for mood in PetMood.allCases where mood != .left && mood != .right { actions.addItem(item(mood.title,#selector(selectMood(_:)),represented:mood.rawValue)) }
        let actionItem=NSMenuItem(title:"表情动作",action:nil,keyEquivalent:"");actionItem.submenu=actions;menu.addItem(actionItem)
        let sizes=NSMenu(title:"大小")
        for (name,w) in [("小巧",144),("标准",192),("大一点",240)] { sizes.addItem(item(name,#selector(selectSize(_:)),represented:w,checked:Int(interactionScale)==w)) }
        let sizeItem=NSMenuItem(title:"大小",action:nil,keyEquivalent:"");sizeItem.submenu=sizes;menu.addItem(sizeItem)
        menu.addItem(item("减少动画",#selector(toggleQuiet),checked:defaults.bool(forKey:"quietAnimations")))
        menu.addItem(.separator())
        let data=NSMenu(title:"会话数据")
        data.addItem(item("跟随最近活跃会话",#selector(followRecent),checked:following))
        if let current=currentSession { data.addItem(item("锁定当前数据会话",#selector(selectSession(_:)),represented:current.id,checked:!following && preferredID==current.id)) }
        data.addItem(.separator())
        for session in sessionList.prefix(12) { data.addItem(item(session.label,#selector(selectSession(_:)),represented:session.id,checked:!following && preferredID==session.id)) }
        let dataItem=NSMenuItem(title:"会话数据",action:nil,keyEquivalent:"");dataItem.submenu=data;menu.addItem(dataItem)
        menu.addItem(item("立即刷新用量",#selector(forceRefresh)))
        menu.addItem(item("使用与数据说明",#selector(showHelp)))
        menu.addItem(.separator())
        let quit=item("退出派小星",#selector(quit));quit.keyEquivalent="q";menu.addItem(quit)
        return menu
    }
    @objc func selectMood(_ sender:NSMenuItem) { if let value=sender.representedObject as? Int,let mood=PetMood(rawValue:value) { perform(mood) } }
    @objc func selectEdge(_ sender:NSMenuItem) {
        guard let value=sender.representedObject as? String,let edge=DockEdge(rawValue:value) else { return }
        manuallyHidden=false;window.orderFrontRegardless()
        updatePosition(window.frame.origin,edge:edge,screen:dockedScreen ?? NSScreen.main!,animate:true)
    }
    @objc func selectSize(_ sender:NSMenuItem) {
        guard let value=sender.representedObject as? Int else { return }
        interactionScale=CGFloat(value);defaults.set(value,forKey:"petWidth")
        updatePosition(window.frame.origin,edge:petView.edge,screen:dockedScreen ?? NSScreen.main!,animate:false)
    }
    @objc func selectSession(_ sender:NSMenuItem) {
        guard let id=sender.representedObject as? String else { return }
        preferredID=id;following=false;defaults.set(id,forKey:"sessionID");defaults.set(false,forKey:"followRecentSession")
        selectionGeneration+=1;snapshot=nil;statsView.update(snapshot:nil,session:nil,message:"正在读取所选会话…",following:false);refreshData(force:true)
    }
    @objc func followRecent() { following=true;defaults.set(true,forKey:"followRecentSession");selectionGeneration+=1;refreshData(force:true) }
    @objc func forceRefresh() { refreshData(force:true) }
    @objc func toggleSnap() {
        snapEnabled.toggle();defaults.set(snapEnabled,forKey:"snapEnabled")
        if !snapEnabled { updatePosition(window.frame.origin,edge:nil,screen:dockedScreen ?? NSScreen.main!,animate:false) }
    }
    @objc func toggleQuiet() { defaults.set(!defaults.bool(forKey:"quietAnimations"),forKey:"quietAnimations");petView.mood = .idle }
    @objc func toggleHidden() { manuallyHidden.toggle();if manuallyHidden { window.orderOut(nil);tooltip.orderOut(nil) } else { window.orderFrontRegardless() } }
    @objc func showAgain() { manuallyHidden=false;window.orderFrontRegardless() }
    @objc func centerPet() {
        manuallyHidden=false
        let screen=NSScreen.main ?? NSScreen.screens[0],area=screen.visibleFrame,size=petSize(in:area)
        updatePosition(CGPoint(x:area.midX-size.width/2,y:area.midY-size.height/2),edge:nil,screen:screen,animate:true)
        window.orderFrontRegardless()
    }
    @objc func screensChanged() {
        guard window != nil else { return }
        let chosen=screen(at:CGPoint(x:window.frame.midX,y:window.frame.midY))
        updatePosition(window.frame.origin,edge:petView.edge,screen:chosen,animate:false)
        tooltip.orderOut(nil)
    }
    @objc func showHelp() {
        let alert=NSAlert();alert.messageText="派小星陪你工作"
        alert.informativeText="拖动：自由摆放；靠近屏幕可用边缘 36 点以内松手，自动吸附并变换姿势。\n双击：跳一下。右键：动作、大小、会话与退出。\n\n悬停约半秒显示上下文用量和账号额度。首次使用默认跟随最近活跃主会话，也可选择并锁定一个会话；不检测当前前台聊天页签。\n\n上下文取最近一轮输入与输出 token 总和，不是逐轮累计消耗。额度是日志快照，账号共享，并标明更新时间；到达重置时间后等待新快照。\n\n程序只在本机读取 Codex 会话元数据和用量事件，不联网、不读取登录凭据。随 Codex 启动联动由配套脚本启用或关闭。屏幕边缘指扣除菜单栏与 Dock 的可用区域。"
        alert.addButton(withTitle:"知道了");NSApp.activate(ignoringOtherApps:true);alert.runModal()
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification:Notification) {
        timer?.invalidate();dataTimer?.invalidate()
        if let window=window,let screen=dockedScreen { savePosition(window.frame.origin,in:screen,edge:petView.edge) }
    }

    func runWindowSmokeTest() {
        var results:[String:Any]=[:]
        let s=NSScreen.main ?? NSScreen.screens[0]
        for edge in DockEdge.allCases {
            updatePosition(window.frame.origin,edge:edge,screen:s,animate:false)
            results[edge.rawValue]=s.visibleFrame.contains(window.frame)
        }
        statsView.update(snapshot:UsageSnapshot(inputTokens:120_000,outputTokens:2000,capacity:475_000,usageDate:Date(),primary:LimitWindow(usedPercent:25,minutes:300,resetsAt:Date().addingTimeInterval(3600)),secondary:LimitWindow(usedPercent:40,minutes:10080,resetsAt:Date().addingTimeInterval(86400)),quotaDate:Date()),session:nil,message:nil,following:false)
        tooltip.setFrameOrigin(Geometry.tooltip(pet:window.frame,size:tooltip.frame.size,area:s.visibleFrame));tooltip.orderFrontRegardless()
        results["tooltipInsideScreen"]=s.visibleFrame.contains(tooltip.frame)
        results["windowTransparent"]=(!window.isOpaque && window.backgroundColor.alphaComponent==0)
        results["noFocusStealing"]=(!window.canBecomeKey)
        perform(.jump);actionUntil=Date().addingTimeInterval(-1);tick()
        results["actionReturnsToIdle"]=(petView.mood == .idle)
        let passed=results.values.allSatisfy { ($0 as? Bool)==true }
        smokePassed=passed
        results["passed"]=passed
        if let d=try? JSONSerialization.data(withJSONObject:results,options:[.sortedKeys]),let text=String(data:d,encoding:.utf8) { print(text) }
        timer?.invalidate();dataTimer?.invalidate()
        NSApp.terminate(nil)
    }
}

import QuartzCore
