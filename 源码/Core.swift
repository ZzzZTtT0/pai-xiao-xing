import Foundation

enum DockEdge: String, Codable, CaseIterable {
    case left, right, top, bottom
    var title: String { switch self { case .left: return "左边探头"; case .right: return "右边探头"; case .top: return "倒挂托腮"; case .bottom: return "趴边托腮" } }
}

enum Geometry {
    static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(max(value, low), max(low, high)) }
    static func constrained(_ origin: CGPoint, size: CGSize, area: CGRect) -> CGPoint {
        CGPoint(x: clamp(origin.x, area.minX, area.maxX-size.width), y: clamp(origin.y, area.minY, area.maxY-size.height))
    }
    static func nearbyEdge(origin: CGPoint, size: CGSize, area: CGRect, threshold: CGFloat = 36) -> DockEdge? {
        let p = constrained(origin, size: size, area: area)
        let choices: [(DockEdge, CGFloat)] = [(.left, abs(p.x-area.minX)), (.right, abs(area.maxX-p.x-size.width)), (.bottom, abs(p.y-area.minY)), (.top, abs(area.maxY-p.y-size.height))]
        guard let result = choices.min(by: {$0.1 < $1.1}), result.1 <= threshold else { return nil }
        return result.0
    }
    static func docked(_ origin: CGPoint, size: CGSize, area: CGRect, edge: DockEdge) -> CGPoint {
        var p = constrained(origin, size: size, area: area)
        switch edge { case .left: p.x=area.minX; case .right: p.x=area.maxX-size.width; case .top: p.y=area.maxY-size.height; case .bottom: p.y=area.minY }
        return p
    }
    static func tooltip(pet: CGRect, size: CGSize, area: CGRect) -> CGPoint {
        var x = pet.maxX+12
        if x+size.width > area.maxX { x = pet.minX-size.width-12 }
        let y = pet.midY-size.height/2
        return constrained(CGPoint(x:x,y:y), size:size, area:area)
    }
}

struct LimitWindow {
    let usedPercent: Double
    let minutes: Double?
    let resetsAt: Date?
    func remaining(at now: Date = Date()) -> Double? {
        if let reset = resetsAt, reset <= now { return nil }
        return max(0, min(100, 100-usedPercent))
    }
    var title: String {
        guard let m = minutes else { return "额度" }
        if m >= 10080 { return "每周额度" }
        if m >= 60 { return "\(Int(m/60)) 小时额度" }
        return "\(Int(m)) 分钟额度"
    }
}

struct UsageSnapshot {
    var inputTokens: Int?
    var outputTokens: Int?
    var capacity: Int?
    var usageDate: Date?
    var primary: LimitWindow?
    var secondary: LimitWindow?
    var quotaDate: Date?
    var contextUsed: Int? {
        guard let i=inputTokens, let o=outputTokens else { return nil }
        let (n, overflow) = i.addingReportingOverflow(o)
        return overflow ? nil : n
    }
    var contextRemaining: Int? {
        guard let c=capacity, c>0, let used=contextUsed else { return nil }
        return max(0,c-used)
    }
    var contextFraction: Double? {
        guard let c=capacity, c>0, let used=contextUsed else { return nil }
        return max(0,min(1,Double(used)/Double(c)))
    }
}

enum LogParser {
    static let fractional: ISO8601DateFormatter = { let f=ISO8601DateFormatter(); f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]; return f }()
    static let standard = ISO8601DateFormatter()
    static func date(_ value: Any?) -> Date? {
        guard let s=value as? String else { return nil }
        return fractional.date(from:s) ?? standard.date(from:s)
    }
    static func integer(_ value: Any?) -> Int? {
        guard let n=value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d=n.doubleValue
        guard d.isFinite, d>=0, d<Double(Int.max), floor(d)==d else { return nil }
        return n.intValue
    }
    static func window(_ value: Any?) -> LimitWindow? {
        guard let d=value as? [String:Any], let n=d["used_percent"] as? NSNumber else { return nil }
        let used=n.doubleValue
        guard used.isFinite else { return nil }
        let reset=(d["resets_at"] as? NSNumber).flatMap { n -> Date? in
            let seconds=n.doubleValue
            return seconds.isFinite && seconds>0 ? Date(timeIntervalSince1970:seconds) : nil
        }
        return LimitWindow(usedPercent:max(0,min(100,used)),minutes:(d["window_minutes"] as? NSNumber)?.doubleValue,resetsAt:reset)
    }
    static func consume(_ data: Data, previous: UsageSnapshot? = nil) -> UsageSnapshot? {
        var result=previous
        for line in data.split(separator:10) {
            // Avoid deserializing conversation messages; token events are small.
            guard line.count < 512_000, line.range(of:Data("token_count".utf8)) != nil,
                  let obj=(try? JSONSerialization.jsonObject(with:Data(line))) as? [String:Any],
                  obj["type"] as? String == "event_msg", let p=obj["payload"] as? [String:Any], p["type"] as? String == "token_count" else { continue }
            var next=result ?? UsageSnapshot()
            let timestamp=date(obj["timestamp"])
            var accepted=false
            if let info=p["info"] as? [String:Any], let last=info["last_token_usage"] as? [String:Any], let input=integer(last["input_tokens"]), let output=integer(last["output_tokens"]) {
                next.inputTokens=input; next.outputTokens=output
                next.capacity=integer(info["model_context_window"])
                next.usageDate=timestamp; accepted=true
            }
            if let limits=p["rate_limits"] as? [String:Any] {
                next.primary=window(limits["primary"]); next.secondary=window(limits["secondary"])
                next.quotaDate=timestamp; accepted=true
            }
            if accepted { result=next }
        }
        return result
    }
}

import CoreFoundation

struct SessionInfo: Equatable {
    let id: String
    let path: URL
    let folder: String
    let modified: Date
    var label: String { "\(folder.isEmpty ? "会话" : folder) · \(id.prefix(8))" }
}

final class SessionReader {
    let home: URL
    private var cachedPath: URL?
    private var offset: UInt64=0
    private var pending=Data()
    private var cached: UsageSnapshot?
    init(home: URL) { self.home=home }

    func sessions(preferredID: String?) -> [SessionInfo] {
        let folder=home.appendingPathComponent("sessions",isDirectory:true)
        guard let iterator=FileManager.default.enumerator(at:folder,includingPropertiesForKeys:[.contentModificationDateKey,.isRegularFileKey],options:[.skipsHiddenFiles]) else { return [] }
        var files: [(URL,Date)]=[]
        for case let url as URL in iterator where url.pathExtension=="jsonl" {
            guard let rv=try? url.resourceValues(forKeys:[.contentModificationDateKey,.isRegularFileKey]),rv.isRegularFile==true else { continue }
            files.append((url,rv.contentModificationDate ?? .distantPast))
        }
        files.sort { $0.1 > $1.1 }
        var candidates=Array(files.prefix(128))
        if let id=preferredID, !candidates.contains(where:{$0.0.lastPathComponent.contains(id)}), let pinned=files.first(where:{$0.0.lastPathComponent.contains(id)}) { candidates.append(pinned) }
        var found: [SessionInfo]=[]
        for (url,modified) in candidates {
            guard let h=try? FileHandle(forReadingFrom:url) else { continue }
            let data=(try? h.read(upToCount:32_768)) ?? Data(); try? h.close()
            guard let first=data.split(separator:10).first,
                  let o=(try? JSONSerialization.jsonObject(with:Data(first))) as? [String:Any],o["type"] as? String=="session_meta",
                  let p=o["payload"] as? [String:Any],let id=p["id"] as? String else { continue }
            if let source=p["source"] as? [String:Any],source["subagent"] != nil { continue }
            let cwd=(p["cwd"] as? String).map { URL(fileURLWithPath:$0).lastPathComponent } ?? "会话"
            found.append(SessionInfo(id:id,path:url,folder:cwd,modified:modified))
        }
        return found.sorted { $0.modified > $1.modified }
    }

    func read(_ session: SessionInfo) -> (UsageSnapshot?,String?) {
        guard let handle=try? FileHandle(forReadingFrom:session.path) else { return (nil,"无法读取会话日志，请检查目录权限") }
        defer { try? handle.close() }
        do {
            let length=try handle.seekToEnd()
            if cachedPath != session.path || length<offset {
                cachedPath=session.path; cached=nil; pending=Data()
                // A bounded initial tail, then only read newly appended bytes.
                offset=length > 16_777_216 ? length-16_777_216 : 0
                if offset>0 {
                    try handle.seek(toOffset:offset)
                    let start=try handle.read(upToCount:262_144) ?? Data()
                    if let newline=start.firstIndex(of:10) { offset+=UInt64(newline+1) }
                }
            }
            try handle.seek(toOffset:offset)
            let data=try handle.read(upToCount:33_554_432) ?? Data()
            offset+=UInt64(data.count)
            pending.append(data)
            if let newline=pending.lastIndex(of:10) {
                let complete=pending.prefix(through:newline)
                cached=LogParser.consume(Data(complete),previous:cached)
                pending=Data(pending.suffix(from:pending.index(after:newline)))
            }
            if pending.count>8_388_608 { pending=Data() }
            return (cached,cached==nil ? "本会话尚无用量记录，完成一轮对话后会更新" : nil)
        } catch { return (cached,"会话日志读取失败：\(error.localizedDescription)") }
    }
}

enum TextFormat {
    static func tokens(_ value: Int?) -> String {
        guard let value=value else { return "—" }
        let f=NumberFormatter();f.numberStyle = .decimal;f.locale=Locale(identifier:"zh_CN")
        return f.string(from:NSNumber(value:value)) ?? "\(value)"
    }
    static func percent(_ value: Double?) -> String {
        guard let value=value, value.isFinite else { return "待更新" }
        return String(format:"%.0f%%",value)
    }
    static func age(_ date: Date?, now: Date = Date()) -> String {
        guard let date=date else { return "更新时间未知" }
        let age=max(0,now.timeIntervalSince(date))
        if age<60 { return "刚刚更新" }
        if age<3600 { return "\(Int(age/60)) 分钟前" }
        if age<86400 { return "\(Int(age/3600)) 小时前" }
        return "\(Int(age/86400)) 天前"
    }
    static func reset(_ window: LimitWindow?, now: Date = Date()) -> String {
        guard let date=window?.resetsAt else { return "重置时间未知" }
        if date<=now { return "已到重置时间，等待新快照" }
        let f=DateFormatter();f.locale=Locale(identifier:"zh_CN");f.dateFormat=Calendar.current.isDateInToday(date) ? "HH:mm '重置'" : "M月d日 HH:mm '重置'"
        return f.string(from:date)
    }
}
