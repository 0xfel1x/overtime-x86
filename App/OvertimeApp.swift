import SwiftUI

@main
enum Main {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--headless" {
            Headless.run(Array(arguments.dropFirst()))
        } else {
            OvertimeApp.main()
        }
    }
}

struct OvertimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = SetupModel()

    var body: some Scene {
        Window("Overtime", id: "main") {
            ContentView(model: model)
                .onAppear {
                    model.autodetect()
                    delegate.developerAids(model)
                }
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Aids for developing this app, switched on by environment variables:
    /// OVERTIME_AUTOSTART=1 starts the setup at launch; OVERTIME_SNAPSHOT=<file.png>
    /// saves a picture of the window after OVERTIME_SNAPSHOT_AFTER seconds
    /// (default 2) and again when the setup ends.
    func developerAids(_ model: SetupModel) {
        let env = ProcessInfo.processInfo.environment
        if env["OVERTIME_AUTOSTART"] == "1" {
            DispatchQueue.main.async { model.start() }
        }
        guard let path = env["OVERTIME_SNAPSHOT"] else { return }
        let delay = Double(env["OVERTIME_SNAPSHOT_AFTER"] ?? "") ?? 2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.snapshot(to: path) }
        model.onFinish = { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.snapshot(to: path.replacingOccurrences(of: ".png", with: "-end.png"))
            }
        }
    }

    private func snapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView, let layer = view.layer else { return }
        let size = view.bounds.size
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { return }
        context.scaleBy(x: 2, y: 2)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        }
        context.fill(CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height)  // the layer tree is flipped
        context.scaleBy(x: 1, y: -1)
        layer.render(in: context)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

/// Command-line mode with the same logic as the window:
///   Overtime --headless [--inspect] [--no-ide] <Xcode.app> <Xcode.app>
enum Headless {
    static func run(_ arguments: [String]) -> Never {
        let model = SetupModel()
        model.withIDE = !arguments.contains("--no-ide")
        model.add(arguments.filter { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) })

        for (label, info) in [("runs here", model.host), ("newer", model.newer)] {
            if let info {
                print("\(label): \(info.name), Xcode \(info.version), SDK \(info.sdkVersion), \(info.archs.joined(separator: "+")), \(info.url.path)")
            } else {
                print("\(label): -")
            }
        }
        if let message = model.notice ?? model.problem ?? model.missing { print("note: \(message)") }
        if arguments.contains("--inspect") { exit(model.canStart ? 0 : 1) }
        guard model.canStart else { exit(1) }

        model.onLine = { print($0) }
        model.onFinish = { success in
            if let result = model.result {
                print("\nresult: SDK \(result.sdkVersion), Swift \(result.swiftVersion)")
                print("xcode copy: \(result.xcodeCopy ?? "-")")
                print("xcconfig: \(result.xcconfig)")
                print("tools: \(result.binFolder)")
            }
            exit(success ? 0 : 1)
        }
        setvbuf(stdout, nil, _IOLBF, 0)
        model.start()
        dispatchMain()
    }
}
