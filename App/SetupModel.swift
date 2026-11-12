import Combine
import Foundation
import SwiftUI

struct SetupStep: Identifiable {
    enum State { case pending, running, done, failed }
    let id: String
    let title: String
    let script: String
    var state: State = .pending
    var detail: String = ""
    var progress: Double?
}

struct SetupResult: Equatable {
    var sdkVersion = ""
    var swiftVersion = ""
    /// Platforms with an SDK copy, as shown to the user (macOS, iOS, tvOS, DriverKit).
    var platforms: [String] = []
    var toolchainName = ""
    /// The Xcode Overtime changed to build with the new SDK.
    var preparedXcode: String?
    /// A separate Xcode copy made by a version before 3.0, no longer needed.
    var unusedCopy: String?
    var xcconfig = ""
    var binFolder = ""
    /// True when Overtime unpacked the newer Xcode itself and removed it again.
    var unpackedXcodeRemoved = false
}

/// Runs the setup scripts one after another and publishes their progress.
/// All state is changed on the main thread.
final class SetupModel: ObservableObject {
    enum Phase { case idle, running, done, failed }

    @Published var host: XcodeInfo?
    @Published var newer: XcodeInfo?
    @Published var notice: String?
    @Published var steps: [SetupStep] = []
    @Published var phase: Phase = .idle
    @Published var log = ""
    @Published var result: SetupResult?
    /// The Xcode prepared earlier, and whether the newer SDK is switched on in it.
    @Published var prepared: (name: String, sdkVersion: String, active: Bool)?
    /// Why the last attempt to switch failed.
    @Published var switchError: String?

    /// Called with every finished output line (used by the command-line mode).
    var onLine: ((String) -> Void)?
    var onFinish: ((Bool) -> Void)?

    let home: URL
    let isAppleSilicon: Bool
    /// macOS of this Mac and the newest Intel-capable Xcode for it.
    let system: OperatingSystemVersion
    let recommendedBase: BaseXcode?
    /// Downloads and unpacks the newest Xcode on request.
    let fetcher: XcodeFetcher
    private var fetcherChanges: AnyCancellable?

    private var process: Process?
    private var cancelled = false
    private var pending = ""

    init() {
        let env = ProcessInfo.processInfo.environment
        if let custom = env["OT_HOME"], !custom.isEmpty {
            home = URL(fileURLWithPath: custom)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Developer/Overtime")
        }
        // An Intel build of this app runs translated on Apple silicon.
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        isAppleSilicon = translated == 1

        // OVERTIME_FAKE_OS=26.4 lets developers try the advice for another macOS.
        var os = ProcessInfo.processInfo.operatingSystemVersion
        let fake = (env["OVERTIME_FAKE_OS"] ?? "").split(separator: ".").compactMap { Int($0) }
        if fake.count >= 2 { os = OperatingSystemVersion(majorVersion: fake[0], minorVersion: fake[1], patchVersion: 0) }
        system = os
        recommendedBase = BaseXcode.recommended(for: os)

        fetcher = XcodeFetcher(workFolder: home.appendingPathComponent("Xcode-download"))
        fetcher.onReady = { [weak self] url in self?.add([url]) }
        fetcherChanges = fetcher.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    var isRunning: Bool { phase == .running }

    /// A reason why the current pair cannot be used, if any.
    var problem: String? {
        if let newer, !newer.hasIntelSwiftInterfaces {
            return "The macOS SDK in \(newer.name) no longer contains Intel support, so it cannot be used."
        }
        if let host, let newer, !Inspector.isNewer(newer.sdkVersion, than: host.sdkVersion) {
            return "\(newer.name) (SDK \(newer.sdkVersion)) is not newer than \(host.name) (SDK \(host.sdkVersion))."
        }
        return nil
    }

    var systemText: String { "macOS \(system.majorVersion).\(system.minorVersion)" }

    /// Advice about the Xcode that runs on this Mac, and whether a download is offered.
    var baseAdvice: (text: String, offer: BaseXcode?)? {
        guard !isAppleSilicon else { return nil }
        guard let best = recommendedBase else {
            let oldest = BaseXcode.all.last!
            return ("This Mac runs \(systemText). The oldest setup Overtime knows is Xcode \(oldest.version) on macOS \(oldest.minimumOSText).", nil)
        }
        let caution = best.tested ? "" : " This combination is not tested by Overtime and may need manual changes."
        guard let host else {
            return ("No Xcode found. For \(systemText) the newest Xcode that runs on Intel is \(best.version).\(caution)", best)
        }
        if Inspector.isNewer(best.version, than: host.version) {
            return ("For \(systemText) the newest Xcode that runs on Intel is \(best.version); yours is \(host.version).\(caution)", best)
        }
        return best.tested ? nil : ("Xcode \(host.version) on \(systemText) is not tested by Overtime and may need manual changes.", nil)
    }

    var missing: String? {
        if fetcher.isBusy { return "Waiting for the newer Xcode." }
        switch (host, newer) {
        case (nil, nil): return "Drop both Xcode apps anywhere in this window."
        case (nil, _): return "Still missing: the Xcode that runs on this Mac."
        case (_, nil): return "Still missing: the newer Xcode. Get it with one click or drop it here."
        default: return nil
        }
    }

    var canStart: Bool {
        !isRunning && !fetcher.isBusy && !isAppleSilicon && host != nil && newer != nil && problem == nil
    }

    // MARK: Switching the SDK on and off

    private func readEnv() -> [String: String] {
        var values: [String: String] = [:]
        // clone.env: the separate Xcode copy made by versions before 3.0.
        for file in ["sdk.env", "toolchain.env", "clone.env", "patch.env"] {
            let text = (try? String(contentsOf: home.appendingPathComponent(file), encoding: .utf8)) ?? ""
            for line in text.split(separator: "\n") {
                guard let eq = line.firstIndex(of: "=") else { continue }
                var value = String(line[line.index(after: eq)...])
                if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") { value = String(value.dropFirst().dropLast()) }
                values[String(line[..<eq])] = value
            }
        }
        return values
    }

    private static func preparedXcode(in env: [String: String]) -> String? {
        env["OT_PATCHED_XCODE"] ?? env["OT_XCODE_CLONE"]
    }

    func refreshPrepared() {
        let env = readEnv()
        guard let xcode = Self.preparedXcode(in: env), let sdk = env["OT_SDK"], let version = env["OT_SDK_VERSION"],
              FileManager.default.fileExists(atPath: xcode) else {
            prepared = nil
            return
        }
        let link = "\(xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX\(version).sdk"
        let active = (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == sdk
        prepared = (URL(fileURLWithPath: xcode).deletingPathExtension().lastPathComponent, version, active)
    }

    /// Switches the SDK link and the name of the prepared Xcode with
    /// scripts/sdk-switch.sh, taken from this app so it is always the current one.
    func setSDK(active: Bool) {
        switchError = nil
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("overtime/scripts/sdk-switch.sh")
        let script = bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? home.appendingPathComponent("scripts/sdk-switch.sh")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [script.path, active ? "on" : "off"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["OT_HOME"] = home.path
        env.removeValue(forKey: "OT_ROOT")
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        do {
            try task.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                let reason = output.split(separator: "\n").last.map(String.init) ?? ""
                switchError = "Could not switch: " + reason.replacingOccurrences(of: "overtime: ", with: "")
            }
        } catch {
            switchError = "Could not switch: \(error.localizedDescription)"
        }
        refreshPrepared()
    }

    // MARK: Choosing the Xcodes

    func autodetect() {
        refreshPrepared()
        let found = Inspector.findInstalled()
        // Prefer an untouched Xcode; fall back to one Overtime prepared earlier.
        // A separate copy left by a version before 3.0 then stays unused.
        let intel = found.filter(\.runsOnIntel)
        host = (intel.filter { !$0.isPrepared }.isEmpty ? intel : intel.filter { !$0.isPrepared })
            .max { Inspector.isNewer($1.version, than: $0.version) }
        newer = found.filter { !$0.runsOnIntel }
            .max { Inspector.isNewer($1.sdkVersion, than: $0.sdkVersion) }
    }

    /// Sorts each dropped Xcode into the right slot by looking at its architecture.
    func add(_ urls: [URL]) {
        guard !isRunning else { return }
        notice = nil
        for url in urls {
            // A packed download is unpacked first and comes back through onReady.
            if url.pathExtension.lowercased() == "xip" {
                fetcher.unpack(url)
                continue
            }
            do {
                var info = try Inspector.inspect(url)
                // An Intel-capable Xcode unpacked by Overtime is one to keep: move
                // it out of the temporary folder into the Applications folder.
                let unpackFolder = fetcher.workFolder.resolvingSymlinksInPath().standardizedFileURL.path
                if info.runsOnIntel, info.url.path.hasPrefix(unpackFolder + "/") {
                    info = try Inspector.inspect(try install(info))
                }
                if info.isPrepared, info.runsOnIntel {
                    host = info
                    notice = "“\(info.name)” was prepared by Overtime before. It will be updated."
                } else if info.runsOnIntel {
                    if let old = host, old.url != info.url, newer == nil {
                        notice = "\(info.name) runs on this Mac, so it replaced \(old.name). The second place is for the newer Xcode that does not open on this Mac."
                    }
                    host = info
                } else {
                    newer = info
                }
            } catch {
                notice = error.localizedDescription
            }
        }
        if phase != .idle {
            phase = .idle
            steps = []
            result = nil
        }
    }

    func startOver() {
        guard !isRunning else { return }
        phase = .idle
        steps = []
        result = nil
        if let newer, !FileManager.default.fileExists(atPath: newer.url.path) { self.newer = nil }
    }

    private func install(_ info: XcodeInfo) throws -> URL {
        let fm = FileManager.default
        var folder = URL(fileURLWithPath: "/Applications")
        if !fm.isWritableFile(atPath: folder.path) {
            folder = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        var target = folder.appendingPathComponent("Xcode.app")
        if fm.fileExists(atPath: target.path) { target = folder.appendingPathComponent("Xcode-\(info.version).app") }
        if fm.fileExists(atPath: target.path) { return info.url }
        try fm.moveItem(at: info.url, to: target)
        return target
    }

    // MARK: Running

    func start() {
        guard canStart else { return }
        cancelled = false
        log = ""
        result = nil
        notice = nil
        steps = [
            SetupStep(id: "sdk", title: "Copy the SDKs", script: "make-sdk.sh"),
            SetupStep(id: "toolchain", title: "Install the matching Swift compiler", script: "install-toolchain.sh"),
            SetupStep(id: "config", title: "Write the project settings", script: "make-xcconfig.sh"),
            SetupStep(id: "ide", title: "Prepare Xcode for the new SDK", script: "patch-xcode.sh"),
        ]
        phase = .running
        do {
            try installTools()
        } catch {
            append("overtime: could not install the tools: \(error.localizedDescription)")
            finish(success: false)
            return
        }
        run(0)
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        cancelled = true
        for pid in descendants(of: process.processIdentifier).reversed() { kill(pid, SIGTERM) }
        process.terminate()
    }

    /// Copies the scripts and wrappers out of the app so they keep working
    /// wherever the app is moved or even after it is deleted.
    private func installTools() throws {
        guard let payload = Bundle.main.resourceURL?.appendingPathComponent("overtime"),
              FileManager.default.fileExists(atPath: payload.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        for folder in ["lib", "scripts", "bin"] {  // includes sdk-switch.sh and ot-sdk
            let target = home.appendingPathComponent(folder)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: payload.appendingPathComponent(folder), to: target)
        }
        append("overtime: tools installed in \(home.path)")
    }

    private func run(_ index: Int) {
        guard index < steps.count, let host, let newer else {
            finish(success: true)
            return
        }
        steps[index].state = .running
        append("\n== \(steps[index].title)")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [home.appendingPathComponent("scripts/\(steps[index].script)").path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["OT_HOME"] = home.path
        env["OT_HOST_XCODE"] = host.url.path
        env["OT_NEW_XCODE"] = newer.url.path
        env.removeValue(forKey: "OT_ROOT")
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            append("overtime: \(error.localizedDescription)")
            steps[index].state = .failed
            finish(success: false)
            return
        }
        process = task

        DispatchQueue.global(qos: .userInitiated).async {
            let reader = pipe.fileHandleForReading
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                let text = String(decoding: chunk, as: UTF8.self)
                DispatchQueue.main.async { self.consume(text, step: index) }
            }
            task.waitUntilExit()
            let status = task.terminationStatus
            DispatchQueue.main.async { self.stepEnded(index, status: status) }
        }
    }

    private func stepEnded(_ index: Int, status: Int32) {
        consume("\n", step: index)
        process = nil
        steps[index].progress = nil
        if status == 0 && !cancelled {
            steps[index].state = .done
            steps[index].detail = ""
            run(index + 1)
        } else {
            steps[index].state = .failed
            if cancelled { steps[index].detail = "Cancelled." }
            finish(success: false)
        }
    }

    private func finish(success: Bool) {
        phase = success ? .done : .failed
        refreshPrepared()
        if success {
            result = loadResult()
            // The Xcode Overtime unpacked itself is only a source for the SDK copy.
            let unpackFolder = fetcher.workFolder.resolvingSymlinksInPath().standardizedFileURL.path
            if let newer, newer.url.path.hasPrefix(unpackFolder + "/") {
                fetcher.cleanUp()
                result?.unpackedXcodeRemoved = true
            }
        }
        onFinish?(success)
    }

    // MARK: Output

    /// Splits script output into lines. A carriage return marks a progress
    /// update (curl), which replaces the step's detail instead of being logged.
    private func consume(_ text: String, step index: Int) {
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n":
                let line = pending
                pending = ""
                finished(line: line, step: index)
            case "\r":
                let line = pending
                pending = ""
                progress(line: line, step: index)
            default:
                pending.unicodeScalars.append(scalar)
            }
        }
    }

    private func finished(line: String, step index: Int) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if progress(line: line, step: index) { return }
        append(trimmed)
        if trimmed.hasPrefix("% Total") || trimmed.hasPrefix("Dload") { return }
        steps[index].detail = trimmed.hasPrefix("overtime: ") ? String(trimmed.dropFirst(10)) : trimmed
    }

    /// Understands a line of curl's transfer meter. Returns false for other text.
    @discardableResult
    private func progress(line: String, step index: Int) -> Bool {
        let fields = line.split(separator: " ")
        guard fields.count >= 12, let percent = Double(fields[0]), percent <= 100,
              fields[10].contains(":") else { return false }
        steps[index].progress = percent / 100
        let left = fields[10].contains("-") ? "" : " · \(fields[10]) left"
        steps[index].detail = "Downloading \(fields[3]) of \(fields[1])\(left)"
        return true
    }

    private func append(_ line: String) {
        log += line + "\n"
        if log.count > 200_000 { log = String(log.suffix(150_000)) }
        onLine?(line)
    }

    // MARK: Result

    private func loadResult() -> SetupResult {
        let values = readEnv()
        let fm = FileManager.default
        var result = SetupResult()
        result.sdkVersion = values["OT_SDK_VERSION"] ?? ""
        result.swiftVersion = values["OT_SWIFT_VERSION"] ?? ""
        let names = ["MacOSX": "macOS", "iPhoneOS": "iOS", "AppleTVOS": "tvOS", "DriverKit": "DriverKit"]
        result.platforms = (values["OT_PLATFORMS"] ?? "MacOSX").split(separator: " ").compactMap { names[String($0)] }
        result.toolchainName = "Swift \(result.swiftVersion)"
        result.xcconfig = home.appendingPathComponent("config/local.xcconfig").path
        result.binFolder = home.appendingPathComponent("bin").path
        result.preparedXcode = Self.preparedXcode(in: values).flatMap { fm.fileExists(atPath: $0) ? $0 : nil }
        result.unusedCopy = values["OT_UNUSED_COPY"].flatMap { fm.fileExists(atPath: $0) ? $0 : nil }
        return result
    }

    private func descendants(of pid: Int32) -> [Int32] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-P", String(pid)]
        let pipe = Pipe()
        task.standardOutput = pipe
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let children = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { Int32($0) }
        return children + children.flatMap { descendants(of: $0) }
    }
}
