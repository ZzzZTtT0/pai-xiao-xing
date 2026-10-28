import Foundation

enum TestFailure: Error { case failed(String) }
func runTests() throws {
    var count=0
    func check(_ value:@autoclosure ()->Bool,_ name:String) throws {
        if !value() { throw TestFailure.failed(name) };count+=1
    }
    let area=CGRect(x:-1200,y:80,width:1200,height:800),size=CGSize(width:192,height:208)
    try check(Geometry.nearbyEdge(origin:CGPoint(x:-1190,y:300),size:size,area:area) == .left,"left snap on negative display coordinates")
    try check(Geometry.nearbyEdge(origin:CGPoint(x:-200,y:300),size:size,area:area) == .right,"right snap")
    try check(Geometry.nearbyEdge(origin:CGPoint(x:-600,y:650),size:size,area:area) == .top,"top snap")
    try check(Geometry.nearbyEdge(origin:CGPoint(x:-600,y:90),size:size,area:area) == .bottom,"bottom snap")
    try check(Geometry.nearbyEdge(origin:CGPoint(x:-600,y:400),size:size,area:area) == nil,"center does not snap")
    try check(Geometry.nearbyEdge(origin:CGPoint(x:-1196,y:82),size:size,area:area) == .bottom,"nearest edge wins in corner")
    for edge in DockEdge.allCases {
        let p=Geometry.docked(CGPoint(x:-9000,y:9000),size:size,area:area,edge:edge)
        try check(area.contains(CGRect(origin:p,size:size)),"docked pose inside available display: \(edge)")
    }
    for p in [CGPoint(x:-1200,y:80),CGPoint(x:-192,y:672),CGPoint(x:-600,y:400)] {
        let card=CGSize(width:344,height:342),origin=Geometry.tooltip(pet:CGRect(origin:p,size:size),size:card,area:area)
        try check(area.contains(CGRect(origin:origin,size:card)),"tooltip remains inside display")
    }

    func event(input:Int=100_000,output:Int=3000,capacity:Any=475_000,used:Double=25) throws -> Data {
        let value:[String:Any] = ["type":"event_msg","timestamp":"2026-10-28T10:00:00.000Z","payload":["type":"token_count","info":["model_context_window":capacity,"total_token_usage":["input_tokens":9_000_000,"output_tokens":100_000],"last_token_usage":["input_tokens":input,"cached_input_tokens":90_000,"output_tokens":output,"reasoning_output_tokens":900]],"rate_limits":["primary":["used_percent":used,"window_minutes":300,"resets_at":4_000_000_000],"secondary":["used_percent":10,"window_minutes":10080,"resets_at":4_000_000_000]]]]
        return try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])+Data([10])
    }
    let data=try event(),s=LogParser.consume(data)!
    try check(s.contextUsed==103_000,"context uses latest turn, not cumulative billing")
    try check(s.contextRemaining==372_000,"context remaining")
    try check(abs((s.contextFraction ?? 0)-103_000.0/475_000)<0.000001,"context ratio")
    try check(s.primary?.remaining()==75,"remaining quota is 100 minus used")
    try check(s.secondary?.title=="每周额度","weekly quota label")
    try check(s.usageDate != nil && s.quotaDate != nil,"record timestamps parsed")
    let noCap=LogParser.consume(try event(capacity:NSNull()))!
    try check(noCap.contextRemaining==nil && noCap.contextFraction==nil,"unknown capacity is unavailable")
    let over=LogParser.consume(try event(input:500_000,output:1000,used:150))!
    try check(over.contextRemaining==0 && over.contextFraction==1 && over.primary?.remaining()==0,"over-limit values clamp")
    try check(LimitWindow(usedPercent:10,minutes:300,resetsAt:Date(timeIntervalSince1970:1)).remaining()==nil,"past reset waits for fresh snapshot")
    try check(LogParser.consume(Data("garbage\n{unfinished".utf8))==nil,"malformed records ignored")
    try check(LogParser.consume(data+Data("{unfinished".utf8))?.contextUsed==103_000,"truncated tail does not lose valid usage")
    try check(LogParser.integer(true)==nil && LogParser.integer(-1)==nil,"invalid token count rejected")
    let fake=Data("{\"type\":\"response_item\",\"payload\":{\"type\":\"token_count\",\"info\":{}}}\n".utf8)
    try check(LogParser.consume(fake)==nil,"non-event records cannot spoof usage")
    let nullLimits=Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"rate_limits\":{\"primary\":null,\"secondary\":null}}}\n".utf8)
    try check(LogParser.consume(nullLimits,previous:s)?.primary==nil,"missing windows are unavailable, not 100 percent")

    let temp=FileManager.default.temporaryDirectory.appendingPathComponent("pai-tests-\(UUID().uuidString)",isDirectory:true)
    defer { try? FileManager.default.removeItem(at:temp) }
    let folder=temp.appendingPathComponent("sessions/2026/10/28",isDirectory:true)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    func meta(_ id:String,_ source:Any="vscode") throws -> Data {
        try JSONSerialization.data(withJSONObject:["type":"session_meta","payload":["id":id,"cwd":"/project/example","source":source]])+Data([10])
    }
    let file=folder.appendingPathComponent("rollout-main.jsonl")
    try (meta("main")+data).write(to:file)
    let child=folder.appendingPathComponent("rollout-child.jsonl")
    try (meta("child",["subagent":["parent_thread_id":"main"]])+data).write(to:child)
    let reader=SessionReader(home:temp)
    let sessions=reader.sessions(preferredID:"main")
    try check(sessions.count==1 && sessions[0].id=="main","subagents excluded from session selection")
    try check(reader.read(sessions[0]).0?.contextUsed==103_000,"real file reader initial parse")
    let next=try event(input:50_000,output:1000),half=next.count/2
    let writer=try FileHandle(forWritingTo:file);try writer.seekToEnd();try writer.write(contentsOf:next.prefix(half))
    try check(reader.read(sessions[0]).0?.contextUsed==103_000,"incomplete appended JSON preserved")
    try writer.write(contentsOf:next.suffix(from:half));try writer.close()
    try check(reader.read(sessions[0]).0?.contextUsed==51_000,"incremental append parsed after completion")
    try (meta("main")+(try event(input:10,output:1))).write(to:file)
    try check(reader.read(sessions[0]).0?.contextUsed==11,"truncated file resets byte offset and cache")
    let missing=SessionInfo(id:"missing",path:folder.appendingPathComponent("absent.jsonl"),folder:"",modified:Date())
    try check(reader.read(missing).0==nil && reader.read(missing).1 != nil,"missing file does not leak previous session usage")
    print("PASS: \(count) checks — snap geometry, multiple displays, quota expiry, log parsing, partial writes, subagent filtering, missing files")
}
