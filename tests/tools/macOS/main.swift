import AppKit

/// Owner of CheckView.xib, which ibtool compiles into a nib.
final class CheckViewController: NSViewController {
    @IBOutlet var label: NSTextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        label.stringValue = ToolCheck.run().joined(separator: "\n")
    }
}

func platformChecks() -> [String] {
    let controller = CheckViewController(nibName: "CheckView", bundle: .main)
    _ = controller.view
    return [
        "nib: \(controller.label == nil ? "missing" : "loaded")",
        "asset color: \(NSColor(named: "AccentColor") == nil ? "missing" : "found")",
    ]
}

// "--check" prints the results and quits; otherwise the window shows them.
if CommandLine.arguments.contains("--check") {
    print((ToolCheck.run() + platformChecks()).joined(separator: "\n"))
    exit(0)
}

let app = NSApplication.shared
let window = NSWindow(contentViewController: CheckViewController(nibName: "CheckView", bundle: .main))
window.title = "ToolCheck"
window.makeKeyAndOrderFront(nil)
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
