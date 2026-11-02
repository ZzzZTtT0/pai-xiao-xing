import Cocoa

extension PetController {
    func runWindowSmokeTest() {
        timer?.invalidate();dataTimer?.invalidate()
        var results:[String:Any]=[:]
        let s=NSScreen.main ?? NSScreen.screens[0]
        var example=SessionInfo(id:"example-session",path:URL(fileURLWithPath:"/fixture/session.jsonl"),folder:"示例项目",modified:Date())
        example.sourceName="Cockpit 示例"
        currentSession=example
        activity=TaskActivity(isRunning:true,operation:"运行测试",updatedAt:Date(),turnID:"example",hasLifecycle:true)
        for edge in DockEdge.allCases {
            updatePosition(window.frame.origin,edge:edge,screen:s,animate:false)
            updateBubble()
            results[edge.rawValue]=s.visibleFrame.contains(window.frame)
            results["bubble_\(edge.rawValue)"]=bubblePanel.isVisible && s.visibleFrame.contains(bubblePanel.frame)
            let origin=Geometry.tooltip(pet:window.frame,size:tooltip.frame.size,area:s.visibleFrame,avoiding:bubblePanel.frame)
            tooltip.setFrameOrigin(origin)
            results["card_\(edge.rawValue)"]=s.visibleFrame.contains(tooltip.frame) && !tooltip.frame.intersects(bubblePanel.frame)
        }
        results["bubbleDoesNotInterceptClicks"]=bubblePanel.ignoresMouseEvents && !bubblePanel.canBecomeKey
        results["bubbleSourceMatchesSession"]=bubbleView.source=="Cockpit 示例" && bubbleView.operation=="运行测试"
        bubblesEnabled=false;updateBubble();results["bubbleToggleHides"]=(!bubblePanel.isVisible);bubblesEnabled=true
        dragging=true;updateBubble();results["dragHidesBubble"]=(!bubblePanel.isVisible);dragging=false
        manuallyHidden=true;updateBubble();results["hiddenPetHidesBubble"]=(!bubblePanel.isVisible);manuallyHidden=false
        currentSession=nil;updateBubble();results["missingSessionHidesBubble"]=(!bubblePanel.isVisible);currentSession=example
        activity.isRunning=false;updateBubble();results["completionHidesBubble"]=(!bubblePanel.isVisible)
        statsView.update(snapshot:UsageSnapshot(inputTokens:120_000,outputTokens:2000,capacity:475_000,usageDate:Date(),primary:LimitWindow(usedPercent:25,minutes:300,resetsAt:Date().addingTimeInterval(3600)),secondary:LimitWindow(usedPercent:40,minutes:10080,resetsAt:Date().addingTimeInterval(86400)),quotaDate:Date()),session:example,message:nil,following:false)
        tooltip.orderFrontRegardless()
        results["windowTransparent"]=(!window.isOpaque && window.backgroundColor.alphaComponent==0)
        results["noFocusStealing"]=(!window.canBecomeKey)
        perform(.jump);actionUntil=Date().addingTimeInterval(-1);tick()
        results["actionReturnsToIdle"]=(petView.mood == .idle)
        activity=TaskActivity(isRunning:true,operation:"运行测试",updatedAt:Date(),turnID:"example",hasLifecycle:true)
        perform(.jump);actionUntil=Date().addingTimeInterval(-1);tick()
        results["actionReturnsToTask"]=(petView.mood == .work)
        let passed=results.values.allSatisfy { ($0 as? Bool)==true };smokePassed=passed;results["passed"]=passed
        if let data=try? JSONSerialization.data(withJSONObject:results,options:[.sortedKeys]),let text=String(data:data,encoding:.utf8) { print(text) }
        NSApp.terminate(nil)
    }
}
