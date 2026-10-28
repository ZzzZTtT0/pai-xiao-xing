import Cocoa

enum AutoStartDecision: String {
    case noCodex, petAlreadyRunning, launchInFlight, launchPet
    static func evaluate(codexRunning:Bool,petRunning:Bool,opening:Bool) -> AutoStartDecision {
        guard codexRunning else { return .noCodex }
        if petRunning { return .petAlreadyRunning }
        if opening { return .launchInFlight }
        return .launchPet
    }
}

final class CodexAutoStarter {
    static let codexID="com.openai.codex"
    static let petID="local.paixiaoxing.desktop"
    let petURL:URL
    var opening=false
    var observer:NSObjectProtocol?

    init(petURL:URL) { self.petURL=petURL }
    static func running(_ identifier:String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier:identifier).contains { !$0.isTerminated }
    }
    static func log(_ text:String) {
        print("\(ISO8601DateFormatter().string(from:Date())) \(text)")
        fflush(stdout)
    }
    func ensurePet(reason:String,completion:((Bool)->Void)?=nil) {
        let decision=AutoStartDecision.evaluate(codexRunning:Self.running(Self.codexID),petRunning:Self.running(Self.petID),opening:opening)
        guard decision == .launchPet else {
            if completion != nil { Self.log("\(reason): \(decision.rawValue)") }
            completion?(true);return
        }
        guard Bundle(url:petURL)?.bundleIdentifier==Self.petID,
              FileManager.default.isExecutableFile(atPath:petURL.appendingPathComponent("Contents/MacOS/PaiXiaoXing").path) else {
            Self.log("派小星应用不存在或不可执行，请重新运行启用联动脚本。")
            completion?(false);return
        }
        opening=true
        let config=NSWorkspace.OpenConfiguration();config.activates=false;config.createsNewApplicationInstance=false
        NSWorkspace.shared.openApplication(at:petURL,configuration:config) { [weak self] app,error in
            DispatchQueue.main.async {
                self?.opening=false
                if let error=error { Self.log("启动失败：\(error.localizedDescription)");completion?(false) }
                else { Self.log("\(reason): 已启动派小星，pid=\(app?.processIdentifier ?? 0)");completion?(app != nil) }
            }
        }
    }
    func start() {
        // Install the observer before the initial check to close the login/startup race.
        observer=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didLaunchApplicationNotification,object:nil,queue:.main) { [weak self] note in
            guard let application=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.bundleIdentifier==Self.codexID else { return }
            self?.ensurePet(reason:"Codex launched")
        }
        Self.log("联动监听已启用，等待 Codex 启动。")
        ensurePet(reason:"Watcher started")
    }
}

let arguments=CommandLine.arguments
if arguments.contains("--self-test") {
    let cases:[(Bool,Bool,Bool,AutoStartDecision)]=[
        (false,false,false,.noCodex),(false,true,false,.noCodex),
        (true,false,false,.launchPet),(true,true,false,.petAlreadyRunning),
        (true,false,true,.launchInFlight),(true,true,true,.petAlreadyRunning)
    ]
    for (codex,pet,opening,expected) in cases {
        if AutoStartDecision.evaluate(codexRunning:codex,petRunning:pet,opening:opening) != expected {
            fputs("FAIL: auto-start state transition\n",stderr);exit(1)
        }
    }
    print("PASS: 6 auto-start decisions; no launch without Codex, no duplicates, in-flight launch suppressed")
    exit(0)
}
if arguments.contains("--status") {
    let state:[String:Any]=["codexBundleID":CodexAutoStarter.codexID,"codexRunning":CodexAutoStarter.running(CodexAutoStarter.codexID),"petRunning":CodexAutoStarter.running(CodexAutoStarter.petID)]
    let data=try! JSONSerialization.data(withJSONObject:state,options:[.sortedKeys]);print(String(data:data,encoding:.utf8)!);exit(0)
}
if arguments.contains("--quit-pet") {
    let pets=NSRunningApplication.runningApplications(withBundleIdentifier:CodexAutoStarter.petID)
    for pet in pets { _=pet.terminate() }
    let until=Date().addingTimeInterval(4)
    while CodexAutoStarter.running(CodexAutoStarter.petID) && Date()<until { RunLoop.current.run(until:Date().addingTimeInterval(0.1)) }
    exit(CodexAutoStarter.running(CodexAutoStarter.petID) ? 1 : 0)
}
guard let index=arguments.firstIndex(of:"--pet-app"),arguments.count>index+1 else {
    fputs("Usage: CodexAutoStart --pet-app <派小星.app> [--ensure-once]\n",stderr);exit(64)
}
let application=NSApplication.shared
application.setActivationPolicy(.prohibited)
let watcher=CodexAutoStarter(petURL:URL(fileURLWithPath:arguments[index+1],isDirectory:true))
if arguments.contains("--ensure-once") {
    DispatchQueue.main.async { watcher.ensurePet(reason:"One-shot check") { ok in exit(ok ? 0 : 1) } }
    DispatchQueue.main.asyncAfter(deadline:.now()+12) { fputs("Timed out launching 派小星\n",stderr);exit(1) }
} else { watcher.start() }
application.run()
