import Foundation

func runActivityTests() throws {
    var checks=0
    func check(_ result:@autoclosure ()->Bool,_ name:String) throws {
        if !result() { throw TestFailure.failed(name) };checks+=1
    }
    let now=Date(timeIntervalSince1970:1_793_600_000)
    func record(_ type:String,_ payload:[String:Any],at date:Date?=nil) throws -> Data {
        try JSONSerialization.data(withJSONObject:["type":type,"timestamp":LogParser.fractional.string(from:date ?? now),"payload":payload],options:[.sortedKeys])+Data([10])
    }
    func start(_ id:String="turn-a",at date:Date?=nil) throws -> Data {
        try record("event_msg",["type":"task_started","turn_id":id,"root_turn_id":id,"started_at":"fixture"],at:date)
    }
    func call(_ name:String,_ input:String,_ custom:Bool=false) throws -> Data {
        var payload:[String:Any]=["type":custom ? "custom_tool_call" : "function_call","name":name,"call_id":"fixture-call"]
        payload[custom ? "input" : "arguments"]=input
        return try record("response_item",payload)
    }
    let begun=ActivityParser.consume(try start())
    try check(begun.bubbleText(at:now)=="分析任务","task start displays a short active bubble")
    let tested=ActivityParser.consume(try call("exec_command","{\"cmd\":\"pytest tests --token SECRET_VALUE\"}"),previous:begun)
    try check(tested.bubbleText(at:now)=="运行测试","function call summarized as tests without raw arguments")
    try check(!(tested.bubbleText(at:now) ?? "").contains("SECRET_VALUE"),"tool arguments never exposed")
    let patched=ActivityParser.consume(try call("exec","await tools.apply_patch('*** Begin Patch ... pytest fixture ...');",true),previous:begun)
    try check(patched.bubbleText(at:now)=="修改代码","nested custom execution recognizes patch operation")
    let searched=ActivityParser.consume(try call("exec_command","{\"cmd\":\"rg --files\"}"),previous:begun)
    try check(searched.bubbleText(at:now)=="查找文件","file search is summarized")
    let read=ActivityParser.consume(try call("exec_command","{\"cmd\":\"sed -n '1,80p' private.txt\"}"),previous:begun)
    try check(read.bubbleText(at:now)=="读取文件","read operation does not show private filename")
    let web=ActivityParser.consume(try call("mcp__codex_apps__search_service_web_run","{}"),previous:begun)
    try check(web.bubbleText(at:now)=="检索资料","web tool gets short operation label")
    let image=ActivityParser.consume(try call("image_gen__imagegen","{}"),previous:begun)
    try check(image.bubbleText(at:now)=="生成图片","image generation label")
    let waited=ActivityParser.consume(try call("wait","{\"cell_id\":\"fixture\"}"),previous:tested)
    try check(waited.bubbleText(at:now)=="运行测试","wait retains meaningful operation")
    let privateThought=try record("response_item",["type":"reasoning","text":"PRIVATE_REASONING"])
    try check(ActivityParser.consume(privateThought,previous:tested).bubbleText(at:now)=="运行测试","reasoning is not rendered in task bubble")
    let finished=ActivityParser.consume(try record("event_msg",["type":"task_complete","turn_id":"turn-a"]),previous:tested)
    try check(finished.bubbleText(at:now)==nil,"finished task bubble disappears")
    let cancelled=ActivityParser.consume(try record("event_msg",["type":"turn_aborted","turn_id":"turn-a"]),previous:tested)
    try check(cancelled.bubbleText(at:now)==nil,"cancelled task bubble disappears")
    let second=ActivityParser.consume(try start("turn-b"),previous:tested)
    let oldCompletion=ActivityParser.consume(try record("event_msg",["type":"task_complete","turn_id":"turn-a"]),previous:second)
    try check(oldCompletion.bubbleText(at:now)=="分析任务","late completion of old turn cannot clear new task")
    let lateCall=ActivityParser.consume(try call("exec_command","{\"cmd\":\"pytest\"}"),previous:finished)
    try check(lateCall.bubbleText(at:now)==nil,"late tool record cannot resurrect completed task")
    try check(tested.bubbleText(at:now.addingTimeInterval(601))==nil,"stale operation bubble expires")
    let partial=ActivityParser.consume(Data("garbage\n{unfinished".utf8),previous:tested)
    try check(partial.bubbleText(at:now)=="运行测试","invalid records preserve prior state")
    let orphan=ActivityParser.consume(try call("exec_command","{\"cmd\":\"swiftc main.swift\"}"))
    try check(orphan.bubbleText(at:now)=="编译构建","tail beginning mid-task can recover current operation")
    let output=ActivityParser.consume(try record("response_item",["type":"function_call_output","call_id":"fixture-call","output":"SECRET_OUTPUT"]))
    try check(output.bubbleText(at:now)==nil,"tool outputs do not create a task bubble")
    let fake=ActivityParser.consume(try record("response_item",["type":"message","role":"user","content":"task_started exec_command pytest SECRET_PROMPT"]))
    try check(fake.bubbleText(at:now)==nil,"message contents cannot spoof task events")
    let fixture=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("pai-activity-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at:fixture) }
    let defaultHome=fixture.appendingPathComponent(".codex")
    let otherHome=fixture.appendingPathComponent(".cockpit_tools/instances/codex/profile-b")
    for root in [defaultHome,otherHome] { try FileManager.default.createDirectory(at:root.appendingPathComponent("sessions"),withIntermediateDirectories:true) }
    let firstFile=defaultHome.appendingPathComponent("sessions/rollout-shared.jsonl")
    let secondFile=otherHome.appendingPathComponent("sessions/rollout-shared.jsonl")
    let meta=try record("session_meta",["id":"shared","source":"vscode","cwd":"/fixture/project"])
    let usage=try record("event_msg",["type":"token_count","info":["model_context_window":1000,"last_token_usage":["input_tokens":100,"output_tokens":12]]])
    try (meta+(try start())+(try call("exec_command","{\"cmd\":\"pytest\"}"))+usage).write(to:firstFile)
    try (meta+(try start())+(try call("apply_patch","fixture patch",true))).write(to:secondFile)
    let reader=SessionReader(home:defaultHome)
    let sessions=reader.sessions(preferredID:nil)
    guard let first=sessions.first(where:{$0.selectionKey==firstFile.path}),let second=sessions.first(where:{$0.selectionKey==secondFile.path}) else { throw TestFailure.failed("activity fixtures discovered") }
    let firstState=reader.readState(first)
    try check(firstState.usage?.contextUsed==112 && firstState.activity.bubbleText(at:now)=="运行测试","incremental reader returns usage and matching task activity")
    try check(reader.readState(second).activity.bubbleText(at:now)=="修改代码","other instance task summary remains isolated")
    try check(reader.readState(first).activity.bubbleText(at:now)=="运行测试","switching between same-ID instance logs cannot mix activity")
    let edit=try call("apply_patch","fixture patch",true),half=edit.count/2
    let writer=try FileHandle(forWritingTo:firstFile);try writer.seekToEnd();try writer.write(contentsOf:edit.prefix(half))
    try check(reader.readState(first).activity.bubbleText(at:now)=="运行测试","partial appended activity JSON waits for complete line")
    try writer.write(contentsOf:edit.suffix(from:half))
    try check(reader.readState(first).activity.bubbleText(at:now)=="修改代码","completed appended activity updates bubble")
    try writer.write(contentsOf:record("event_msg",["type":"task_complete","turn_id":"turn-a"]))
    try writer.close()
    try check(reader.readState(first).activity.bubbleText(at:now)==nil,"incremental task completion hides bubble")

    let replacementFile=defaultHome.appendingPathComponent("sessions/replace.jsonl")
    let replacementSession=SessionInfo(id:"shared",path:replacementFile,folder:"fixture",modified:now)
    let original=meta+(try start())+(try call("exec_command","{\"cmd\":\"pytest\"}"))+usage
    try original.write(to:replacementFile)
    try check(reader.readState(replacementSession).usage?.contextUsed==112,"replacement fixture initial usage")
    let replacementUsage=try record("event_msg",["type":"token_count","info":["model_context_window":1000,"last_token_usage":["input_tokens":200,"output_tokens":12]]])
    let sameSize=meta+(try start())+(try call("exec_command","{\"cmd\":\"cat aa\"}"))+replacementUsage
    try check(original.count==sameSize.count,"equal-size replacement fixture has exact byte length")
    try sameSize.write(to:replacementFile,options:.atomic)
    let replaced=reader.readState(replacementSession)
    try check(replaced.usage?.contextUsed==212 && replaced.activity.bubbleText(at:now)=="读取文件","equal-length atomic log replacement discards cached state")
    let padding=try record("response_item",["type":"message","role":"user","content":String(repeating:"x",count:4000)])
    let larger=padding+meta+(try start())+(try call("apply_patch","fixture",true))
    try larger.write(to:replacementFile,options:.atomic)
    let bigger=reader.readState(replacementSession)
    try check(bigger.usage==nil && bigger.activity.bubbleText(at:now)=="修改代码","larger replacement does not retain previous account usage")
    let rewound=try FileHandle(forWritingTo:replacementFile)
    try rewound.truncate(atOffset:0)
    let morePadding=try record("response_item",["type":"message","role":"user","content":String(repeating:"y",count:8000)])
    try rewound.write(contentsOf:morePadding+meta);try rewound.close()
    try check(reader.readState(replacementSession).activity.bubbleText(at:now)==nil,"in-place truncate-and-regrow resets a stale task bubble")

    let customHome=fixture.appendingPathComponent("custom-home")
    let instanceRoot=fixture.appendingPathComponent(".cockpit_tools/instances/codex")
    let nested=instanceRoot.appendingPathComponent("nested/.codex")
    for root in [customHome,instanceRoot.appendingPathComponent("samepref-A"),instanceRoot.appendingPathComponent("samepref-B"),nested] {
        try FileManager.default.createDirectory(at:root.appendingPathComponent("sessions"),withIntermediateDirectories:true)
        try meta.write(to:root.appendingPathComponent("sessions/rollout-shared.jsonl"))
    }
    let groupedReader=SessionReader(home:customHome,cockpitRoot:instanceRoot,additionalHomes:[defaultHome])
    let sources=groupedReader.sources()
    try check(sources.count==6 && Set(sources.map(\.label)).count==6,"custom/default roots and similar Cockpit names have distinguishable source groups")
    try check(groupedReader.sessions(preferredID:nil).contains(where:{$0.selectionKey.hasPrefix(nested.path+"/")}),"nested .codex Cockpit session root is discovered")

    var legacy=SessionBinding(id:"shared",path:nil)
    let migrated=legacy.resolve(in:[second,first],following:false,legacyHome:defaultHome)
    try check(migrated?.selectionKey==first.selectionKey && legacy.path==first.selectionKey,"legacy ID-only lock migrates to canonical source path")
    try check(legacy.resolve(in:[second,first],following:false,legacyHome:defaultHome)?.selectionKey==first.selectionKey,"locked instance remains fixed after discovery order changes")
    try check(legacy.resolve(in:[second],following:false,legacyHome:defaultHome)==nil,"missing locked source must not fall back to another same-ID account")
    var explicit=SessionBinding(id:"shared",path:second.selectionKey)
    try check(explicit.resolve(in:[first,second],following:false,legacyHome:defaultHome)?.selectionKey==second.selectionKey,"explicit Cockpit lock resolves exact instance")
    try check(explicit.resolve(in:[first,second],following:true,legacyHome:defaultHome)?.selectionKey==first.selectionKey,"follow mode tracks most recent input ordering instead of old lock")

    let area=CGRect(x:-1200,y:80,width:1200,height:800),petSize=CGSize(width:192,height:208),bubbleSize=CGSize(width:238,height:84)
    for edge in DockEdge.allCases {
        let origin=Geometry.docked(CGPoint(x:-600,y:400),size:petSize,area:area,edge:edge)
        let pet=CGRect(origin:origin,size:petSize)
        let layout=Geometry.activityBubble(pet:pet,size:bubbleSize,area:area,edge:edge)
        try check(area.contains(layout.frame),"\(edge) activity bubble stays in visible screen")
        try check(layout.tailX>=14 && layout.tailX<=bubbleSize.width-14,"bubble tail avoids rounded corners")
        if edge == .top { try check(layout.tailAtTop,"top-edge bubble flips under visible head") }
        if edge == .bottom { try check(!layout.tailAtTop,"bottom-edge bubble stays above visible head") }
        let cardSize=CGSize(width:344,height:342)
        let card=CGRect(origin:Geometry.tooltip(pet:pet,size:cardSize,area:area,avoiding:layout.frame),size:cardSize)
        try check(area.contains(card) && !card.intersects(layout.frame),"hover card avoids task bubble when screen has room")
    }
    print("PASS: \(checks) activity, incremental isolation and bubble placement checks")
}
