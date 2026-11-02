import Foundation

struct TaskActivity {
    var isRunning=false
    var operation="分析任务"
    var updatedAt:Date?
    var turnID:String?
    var hasLifecycle=false

    func bubbleText(at now:Date=Date()) -> String? {
        guard isRunning,let updatedAt=updatedAt,
              now.timeIntervalSince(updatedAt) < 600,now.timeIntervalSince(updatedAt) > -300 else { return nil }
        return operation
    }
}

enum ActivityParser {
    static func consume(_ data:Data,previous:TaskActivity=TaskActivity()) -> TaskActivity {
        var result=previous
        for line in data.split(separator:10) {
            guard line.count<512_000,
                  let object=(try? JSONSerialization.jsonObject(with:Data(line))) as? [String:Any],
                  let payload=object["payload"] as? [String:Any],let kind=payload["type"] as? String else { continue }
            let timestamp=LogParser.date(object["timestamp"])
            if object["type"] as? String == "event_msg" {
                if ["task_started","turn_started"].contains(kind) {
                    result.isRunning=true;result.hasLifecycle=true;result.operation="分析任务"
                    result.turnID=payload["turn_id"] as? String ?? payload["root_turn_id"] as? String
                    result.updatedAt=timestamp
                } else if ["task_complete","task_completed","turn_complete","turn_completed","turn_aborted","task_cancelled","task_canceled","task_failed"].contains(kind) {
                    let endedID=payload["turn_id"] as? String ?? payload["root_turn_id"] as? String
                    if let current=result.turnID,let endedID=endedID,current != endedID { continue }
                    result.isRunning=false;result.hasLifecycle=true;result.updatedAt=timestamp
                } else if kind == "token_count",result.isRunning,let timestamp=timestamp {
                    result.updatedAt=timestamp
                }
            } else if object["type"] as? String == "response_item",["function_call","custom_tool_call"].contains(kind) {
                // A bounded initial log tail may begin after task_started.
                guard result.isRunning || !result.hasLifecycle else { continue }
                guard let name=payload["name"] as? String else { continue }
                let input=payload["arguments"] as? String ?? payload["input"] as? String ?? ""
                result.isRunning=true;result.updatedAt=timestamp ?? result.updatedAt
                if let summary=OperationSummary.text(name:name,input:input) { result.operation=summary }
            }
        }
        return result
    }
}

enum OperationSummary {
    static func text(name:String,input:String) -> String? {
        let tool=name.lowercased()
        let code=String(input.prefix(16_384)).lowercased()
        let short=tool.split(separator:".").last.map(String.init) ?? tool
        if ["wait","write_stdin","wait_agent","sleep"].contains(short) { return nil }
        if tool.contains("apply_patch") || code.contains("tools.apply_patch") { return "修改代码" }
        if tool.contains("imagegen") || code.contains("image_gen__imagegen") { return "生成图片" }
        if tool.contains("web_run") || tool.contains("web__run") || code.contains("tools.web__run") || code.contains("search_service_web_run") { return "检索资料" }
        if tool.contains("github") || code.contains("mcp__codex_apps__github") { return "处理 GitHub 仓库" }
        if tool.contains("spawn_agent") || tool.contains("send_message") || tool.contains("followup_task") { return "协调子任务" }
        if tool.contains("view_image") || code.contains("tools.view_image") { return "检查图像" }
        if short == "exec" || tool.contains("exec_command") || short == "js" {
            if code.contains("write_stdin") && !code.contains("exec_command") { return nil }
            if matches(code,#"\b(pytest|cargo\s+test|swift\s+test|go\s+test|(?:npm|pnpm)\s+(?:run\s+)?test)\b|--(?:self|render|smoke)-test"#) { return "运行测试" }
            if matches(code,#"\b(swiftc|xcodebuild|clang|cmake|make)\b|(?:npm|pnpm)\s+(?:run\s+)?build"#) { return "编译构建" }
            if code.contains("swiftc") { return "编译构建" }
            if matches(code,#"\bgit\s+(status|diff|log)\b"#) { return "检查代码变更" }
            if matches(code,#"\bgit\s+(push|pull|fetch|clone)\b"#) { return "同步代码仓库" }
            if matches(code,#"\b(rg|grep|find)\s"#) { return "查找文件" }
            if matches(code,#"\b(cat|sed|head|tail)\s|readfile\("#) { return "读取文件" }
            return "执行脚本"
        }
        return "执行工具操作"
    }

    private static func matches(_ text:String,_ pattern:String) -> Bool {
        text.range(of:pattern,options:.regularExpression) != nil
    }
}
