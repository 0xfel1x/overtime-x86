import AppKit
import Foundation

/// Gets the newest Xcode with the user's own Apple Account.
///
/// Overtime never downloads Apple software itself and never sees the account:
/// it reads the newest version from Apple's public release feed, opens Apple's
/// download link in the user's browser, waits for the finished .xip in the
/// Downloads folder and unpacks it with the system's own `xip` tool.
final class XcodeFetcher: ObservableObject {
    enum Phase { case idle, lookingUp, waiting, unpacking, failed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var status = ""
    @Published private(set) var version: String?

    /// Called with the unpacked Xcode app.
    var onReady: ((URL) -> Void)?
    var opensBrowser = true
    /// Where the .xip is unpacked. Removed again by `cleanUp()`.
    let workFolder: URL

    static let feed = URL(string: "https://developer.apple.com/news/releases/rss/releases.rss")!
    static let downloadPage = URL(string: "https://developer.apple.com/download/applications/")!

    private var timer: DispatchSourceTimer?
    private var process: Process?
    private var started = Date()

    init(workFolder: URL) {
        self.workFolder = workFolder
    }

    var isBusy: Bool { phase == .lookingUp || phase == .waiting || phase == .unpacking }

    /// Apple's download link for the newest release; it asks for the Apple Account first.
    var downloadURL: URL {
        guard let version,
              let url = URL(string: "https://developer.apple.com/services-account/download?path=/Developer_Tools/Xcode_\(version)/Xcode_\(version).xip")
        else { return Self.downloadPage }
        return url
    }

    // MARK: Steps

    func start() {
        guard !isBusy else { return }
        started = Date()
        version = nil
        phase = .lookingUp
        status = "Looking up the newest Xcode at Apple…"
        var request = URLRequest(url: Self.feed)
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let newest = Self.newestRelease(inFeed: text)
            DispatchQueue.main.async {
                guard self.phase == .lookingUp else { return }
                self.version = newest
                self.waitForDownload()
            }
        }.resume()
    }

    /// Newest final release named in Apple's feed, for example "27.2". Betas and
    /// release candidates carry extra words in the title and do not match.
    static func newestRelease(inFeed text: String) -> String? {
        guard let pattern = try? NSRegularExpression(pattern: "<title>Xcode ([0-9]+(?:\\.[0-9]+)*) \\([0-9A-Za-z]+\\)</title>") else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let versions = pattern.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
        return versions.max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    private func waitForDownload() {
        if let xip = finishedDownload() {
            unpack(xip)
            return
        }
        if opensBrowser { NSWorkspace.shared.open(downloadURL) }
        phase = .waiting
        status = waitingText(downloaded: 0)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self, self.phase == .waiting else { return }
            if let xip = self.finishedDownload() {
                self.unpack(xip)
            } else {
                self.status = self.waitingText(downloaded: self.partialBytes())
            }
        }
        timer.resume()
        self.timer = timer
    }

    private func waitingText(downloaded: Int64) -> String {
        let name = version.map { "Xcode \($0)" } ?? "the newest Xcode"
        if downloaded > 0 {
            let amount = ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
            return "Your browser is downloading \(name): \(amount) so far. Overtime continues by itself when it is finished."
        }
        return "Your browser opens Apple's download of \(name). Sign in with your Apple Account there; Overtime continues by itself when the download is finished. You can also drop the downloaded .xip file here."
    }

    /// Unpacks a downloaded .xip. Also used when the user drops a .xip on the window.
    func unpack(_ xip: URL) {
        guard phase != .unpacking else { return }
        stopTimer()
        let fm = FileManager.default
        let parent = workFolder.deletingLastPathComponent()
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)

        let size = Int64((try? xip.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let needed = max(size * 6, 15_000_000_000)
        let free = (try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage) ?? Int64.max
        guard free >= needed else {
            let amount = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
            fail("Not enough free disk space to unpack Xcode. About \(amount) are needed.")
            return
        }

        try? fm.removeItem(at: workFolder)
        do {
            try fm.createDirectory(at: workFolder, withIntermediateDirectories: true)
        } catch {
            fail(error.localizedDescription)
            return
        }

        phase = .unpacking
        status = "Unpacking \(xip.lastPathComponent). This takes several minutes."
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xip")
        task.arguments = ["--expand", xip.path]
        task.currentDirectoryURL = workFolder
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.terminationHandler = { finished in
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            DispatchQueue.main.async {
                guard self.process === finished else { return }
                self.process = nil
                self.unpacked(status: finished.terminationStatus, output: output)
            }
        }
        do {
            try task.run()
            process = task
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func unpacked(status code: Int32, output: String) {
        let apps = ((try? FileManager.default.contentsOfDirectory(at: workFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" }
        guard code == 0, let app = apps.first else {
            let reason = output.split(separator: "\n").last.map(String.init) ?? "xip ended with code \(code)"
            fail("Unpacking failed: \(reason)")
            return
        }
        phase = .idle
        status = ""
        onReady?(app)
    }

    func cancel() {
        stopTimer()
        let running = process
        process = nil
        running?.terminate()
        phase = .idle
        status = ""
        cleanUp()
    }

    /// Removes the unpacked Xcode. The SDK copy made from it is independent.
    func cleanUp() {
        try? FileManager.default.removeItem(at: workFolder)
    }

    private func fail(_ message: String) {
        stopTimer()
        phase = .failed
        status = message
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: Downloads folder

    private var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    private func isWanted(_ fileName: String, modified: Date?) -> Bool {
        let name = fileName.lowercased()
        guard name.hasPrefix("xcode"), !name.contains("beta"), !name.contains("candidate") else { return false }
        if let version {
            return ["xcode_\(version).", "xcode_\(version)_", "xcode_\(version) "].contains { name.hasPrefix($0) }
        }
        // Version unknown: only accept what arrived after the button was clicked.
        return (modified ?? .distantPast) > started.addingTimeInterval(-60)
    }

    /// A complete .xip: browsers keep unfinished downloads under another name
    /// (.download, .part, .crdownload), and the file must have stopped changing.
    private func finishedDownload() -> URL? {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let items = try? fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: keys) else { return nil }
        for item in items where item.pathExtension.lowercased() == "xip" {
            let values = try? item.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) > 500_000_000,
                  isWanted(item.lastPathComponent, modified: values?.contentModificationDate) else { continue }
            let unfinished = [".download", ".part", ".crdownload"].contains { fm.fileExists(atPath: item.path + $0) }
            let age = Date().timeIntervalSince(values?.contentModificationDate ?? Date())
            if !unfinished && age > 10 { return item }
        }
        return nil
    }

    /// Size of downloads that are still running, to show that something happens.
    private func partialBytes() -> Int64 {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        guard let items = try? fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for item in items where ["download", "part", "crdownload"].contains(item.pathExtension.lowercased()) {
            let values = try? item.resourceValues(forKeys: Set(keys))
            guard (values?.contentModificationDate ?? .distantPast) > started.addingTimeInterval(-60) else { continue }
            if values?.isDirectory == true {
                let inner = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                for file in inner { total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            } else {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}
