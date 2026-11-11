import Foundation

/// What Overtime needs to know about one Xcode installation. Everything is read
/// from files inside the bundle; the Xcode itself is never launched or changed.
struct XcodeInfo: Equatable {
    let url: URL
    let version: String
    let sdkVersion: String
    let archs: [String]
    let hasIntelSwiftInterfaces: Bool
    /// True for the private copy made by scripts/make-xcode-clone.sh.
    let isOvertimeCopy: Bool

    var runsOnIntel: Bool { archs.contains("x86_64") }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

enum InspectError: LocalizedError {
    case xip(String)
    case notApp(String)
    case notXcode(String)
    case noSDK(String)
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .xip(let name):
            return "“\(name)” is still packed. Double-click it in the Finder to unpack it, then drop the Xcode app that appears."
        case .notApp(let name):
            return "“\(name)” is not an app. Drop the Xcode apps themselves."
        case .notXcode(let name):
            return "“\(name)” is not Xcode."
        case .missing(let name):
            return "“\(name)” was not found. It may have been moved or deleted."
        case .noSDK(let name):
            return "“\(name)” contains no macOS SDK. It may be incomplete; unpack it again."
        }
    }
}

enum Inspector {
    private static let sdksPath = "Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs"

    static func inspect(_ rawURL: URL) throws -> XcodeInfo {
        let url = rawURL.resolvingSymlinksInPath().standardizedFileURL
        let fileName = url.lastPathComponent
        guard FileManager.default.fileExists(atPath: url.path) else { throw InspectError.missing(fileName) }
        switch url.pathExtension.lowercased() {
        case "xip": throw InspectError.xip(fileName)
        case "app": break
        default: throw InspectError.notApp(fileName)
        }

        let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        guard plist?["CFBundleIdentifier"] as? String == "com.apple.dt.Xcode" else {
            throw InspectError.notXcode(fileName)
        }
        let version = plist?["CFBundleShortVersionString"] as? String ?? "?"

        let sdks = url.appendingPathComponent(sdksPath)
        let sdk = sdks.appendingPathComponent("MacOSX.sdk")
        let settings = NSDictionary(contentsOf: sdk.appendingPathComponent("SDKSettings.plist"))
        guard let sdkVersion = settings?["Version"] as? String else {
            throw InspectError.noSDK(fileName)
        }

        let fm = FileManager.default
        let interface = sdk.appendingPathComponent("usr/lib/swift/Swift.swiftmodule/x86_64-apple-macos.swiftinterface")
        // The private copy carries a symlink to an SDK outside its own bundle.
        let entries = (try? fm.contentsOfDirectory(atPath: sdks.path)) ?? []
        let isCopy = entries.contains { entry in
            let target = try? fm.destinationOfSymbolicLink(atPath: sdks.appendingPathComponent(entry).path)
            return target?.hasPrefix("/") ?? false
        }

        return XcodeInfo(
            url: url,
            version: version,
            sdkVersion: sdkVersion,
            archs: machOArchs(url.appendingPathComponent("Contents/MacOS/Xcode")),
            hasIntelSwiftInterfaces: fm.fileExists(atPath: interface.path),
            isOvertimeCopy: isCopy
        )
    }

    /// CPU architectures of a Mach-O file, read from its header.
    static func machOArchs(_ url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 4096)
        guard data.count >= 8 else { return [] }

        func be32(_ offset: Int) -> UInt32 {
            guard offset + 4 <= data.count else { return 0 }
            return data[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        func name(_ cpuType: UInt32) -> String {
            switch cpuType {
            case 0x0100_0007: return "x86_64"
            case 0x0100_000C: return "arm64"
            case 0x0000_0007: return "i386"
            default: return String(format: "cpu-%08x", cpuType)
            }
        }

        switch be32(0) {
        case 0xCAFE_BABE, 0xCAFE_BABF:  // universal file, big-endian header
            let entrySize = be32(0) == 0xCAFE_BABE ? 20 : 32
            let count = Int(min(be32(4), 16))
            return (0..<count).map { name(be32(8 + $0 * entrySize)) }
        case 0xCFFA_EDFE:  // 64-bit Mach-O, little-endian
            return [name(be32(4).byteSwapped)]
        default:
            return []
        }
    }

    /// Xcode apps in the usual places, without the copies Overtime made itself.
    static func findInstalled() -> [XcodeInfo] {
        let fm = FileManager.default
        let folders = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
        ]
        var found: [XcodeInfo] = []
        for folder in folders {
            let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for item in items where item.pathExtension == "app" && item.lastPathComponent.hasPrefix("Xcode") {
                if let info = try? inspect(item), !info.isOvertimeCopy { found.append(info) }
            }
        }
        return found
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }
}
