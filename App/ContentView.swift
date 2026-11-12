import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: SetupModel
    @State private var dropTargeted = false
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Overtime").font(.largeTitle.bold())
                Text("Build with the newest macOS SDK on an Intel Mac. Overtime finds your Xcode and gets the newest one with one click; you can also drop Xcode apps here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let prepared = model.prepared, !model.isRunning {
                SwitchView(prepared: prepared) { model.setSDK(active: $0) }
            }

            if let result = model.result {
                ResultView(result: result)
                Button("Start Over") { model.startOver() }
            } else {
                setup
            }

            if !model.log.isEmpty {
                DisclosureGroup("Details", isExpanded: $showLog) {
                    ScrollView {
                        Text(model.log)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 140)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Text("Release \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · Overtime by 0xfel1x")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(22)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        // Keep the window exactly as large as its content (works on macOS 12 too).
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { fitWindow(geometry.size) }
                .onChange(of: geometry.size) { fitWindow($0) }
        })
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { model.add([url]) }
                }
            }
            return true
        }
        .onChange(of: model.phase) { phase in
            if phase == .failed { showLog = true }
        }
    }

    @ViewBuilder private var setup: some View {
        if model.isAppleSilicon {
            Label("This Mac has Apple silicon. The newest Xcode runs here directly, so Overtime is not needed.",
                  systemImage: "info.circle.fill")
                .foregroundStyle(.blue)
        }

        VStack(spacing: 10) {
            SlotView(title: "Xcode that runs on this Mac",
                     placeholder: "Drop the Xcode you use today",
                     info: model.host, highlighted: dropTargeted) { choose() }
            if let advice = model.baseAdvice {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(advice.text).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let offer = advice.offer {
                        Button("Get Xcode \(offer.version)") { NSWorkspace.shared.open(offer.downloadURL) }
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 4)
            }
            if model.fetcher.phase == .idle {
                SlotView(title: "Newer Xcode (only its SDK is read)",
                         placeholder: "Drop it here or get it",
                         info: model.newer, highlighted: dropTargeted,
                         primaryTitle: model.newer == nil ? "Get Newest Xcode" : nil,
                         primary: { model.fetcher.start() }) { choose() }
            } else {
                FetchView(fetcher: model.fetcher)
            }
        }
        .disabled(model.isRunning)

        if let warning = model.notice ?? model.problem {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !model.isRunning {
            Toggle(isOn: $model.withIDE) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Also prepare Xcode itself")
                    Text("Puts a private copy of your Xcode that builds with the new SDK into the Applications folder. It takes almost no extra disk space, and your installed Xcode stays untouched.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        HStack(spacing: 12) {
            if model.isRunning {
                Button("Cancel") { model.cancel() }.controlSize(.large)
            } else {
                Button(model.phase == .failed ? "Try Again" : "Set Up") { model.start() }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStart)
            }
            Text(statusText).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !model.steps.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.steps) { StepRow(step: $0) }
            }
        }
    }

    private var statusText: String {
        switch model.phase {
        case .running: return "Working. The compiler download can take a few minutes."
        case .failed: return "Stopped. See the marked step and the details below."
        case .done, .idle: return model.missing ?? (model.problem == nil ? "Ready." : "")
        }
    }

    private func fitWindow(_ size: CGSize) {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            let top = window.frame.maxY
            window.setContentSize(size)
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose one or both Xcode apps"
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}

private struct SlotView: View {
    let title: String
    let placeholder: String
    let info: XcodeInfo?
    let highlighted: Bool
    var primaryTitle: String?
    var primary: () -> Void = {}
    let choose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let info {
                Image(nsImage: NSWorkspace.shared.icon(forFile: info.url.path))
                    .resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text("\(info.name) · Xcode \(info.version)").font(.headline)
                    Text("macOS SDK \(info.sdkVersion) · \(info.url.path)")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            } else {
                Image(systemName: "arrow.down.app")
                    .font(.system(size: 30)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(placeholder)
                }
            }
            Spacer(minLength: 8)
            if let primaryTitle {
                Button(primaryTitle, action: primary).buttonStyle(.borderedProminent)
            }
            Button("Choose…", action: choose)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(highlighted ? Color.accentColor : Color.secondary.opacity(0.45),
                              style: StrokeStyle(lineWidth: 1.5, dash: info == nil ? [6, 4] : []))
        )
    }
}

/// On/off switch for the newer SDK in the Xcode prepared earlier.
private struct SwitchView: View {
    let prepared: (name: String, sdkVersion: String, active: Bool)
    let set: (Bool) -> Void

    var body: some View {
        GroupBox {
            Toggle(isOn: Binding(get: { prepared.active }, set: set)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use macOS SDK \(prepared.sdkVersion) in “\(prepared.name)”").font(.headline)
                    Text(prepared.active
                         ? "On: projects build with the new SDK. Plain swiftc and swift build in the Terminal can fail with it; use ot-swiftc and ot-swift there, or switch off."
                         : "Off: this Xcode behaves exactly as before, in its window and in the Terminal. Switch on to build with the new SDK.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Restart Xcode after switching.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Shown in place of the second slot while Overtime gets the newest Xcode.
private struct FetchView: View {
    @ObservedObject var fetcher: XcodeFetcher

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if fetcher.phase == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26)).foregroundStyle(.orange)
                } else if fetcher.progress != nil {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 26)).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(fetcher.version.map { "Getting Xcode \($0)" } ?? "Getting the newest Xcode")
                    .font(.headline)
                Text(fetcher.status)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = fetcher.progress {
                    ProgressView(value: progress)
                }
                HStack {
                    if fetcher.phase == .waiting {
                        Button("Open Download Again") { NSWorkspace.shared.open(fetcher.downloadURL) }
                        Button("All Xcode Downloads") { NSWorkspace.shared.open(XcodeFetcher.downloadPage) }
                    }
                    Button(fetcher.phase == .failed ? "OK" : "Cancel") { fetcher.cancel() }
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
        )
    }
}

private struct StepRow: View {
    let step: SetupStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                switch step.state {
                case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
                case .running: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                if !step.detail.isEmpty && step.state != .pending {
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(step.state == .failed ? Color.red : Color.secondary)
                        .lineLimit(3).truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if let progress = step.progress {
                    ProgressView(value: progress)
                }
            }
        }
    }
}

private struct ResultView: View {
    let result: SetupResult

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("Ready: macOS SDK \(result.sdkVersion) with Swift \(result.swiftVersion)",
                      systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(.green)

                if let copy = result.xcodeCopy {
                    let name = URL(fileURLWithPath: copy).deletingPathExtension().lastPathComponent
                    row(title: "In Xcode",
                        text: "Open your projects with “\(name)”. It builds with the new SDK and the matching Swift compiler by itself; nothing needs to be changed in the project.") {
                        Button("Open \(name)") { NSWorkspace.shared.open(URL(fileURLWithPath: copy)) }
                        Button("Show in Finder") { reveal(copy) }
                    }
                } else {
                    row(title: "In Xcode",
                        text: "Not prepared. To build in the Xcode window, start over and switch on “Also prepare Xcode itself”.") {
                        EmptyView()
                    }
                }
                row(title: "In Terminal",
                    text: "ot-swiftc, ot-swift, ot-clang and ot-clang++ build with the new SDK. Add them to your shell once with the PATH line.") {
                    Button("Copy PATH Line") { copy("export PATH=\"\(result.binFolder):$PATH\"") }
                    Button("Show in Finder") { reveal(result.binFolder) }
                }
                Text(result.unpackedXcodeRemoved
                     ? "Overtime removed the unpacked newer Xcode again. The downloaded .xip file in your Downloads folder can be deleted too."
                     : "The newer Xcode is no longer needed and can be moved to the Trash. Keep it only if you want to run this setup again.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row<Buttons: View>(title: String, text: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack { buttons() }.controlSize(.small)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
