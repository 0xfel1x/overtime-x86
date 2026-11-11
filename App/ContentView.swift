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
                Text("Build with the newest macOS SDK on an Intel Mac. Drop both Xcode apps here; Overtime works out which is which.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        }
        .padding(22)
        .frame(width: 600)
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
            SlotView(title: "Newer Xcode (only its SDK is read)",
                     placeholder: "Drop the newer Xcode that does not open on this Mac",
                     info: model.newer, highlighted: dropTargeted) { choose() }
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
                    Text("Makes a private copy of your Xcode that builds with the new SDK. It takes almost no extra disk space, and your installed Xcode stays untouched.")
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
                Text("The newer Xcode is no longer needed and can be moved to the Trash. Keep it only if you want to run this setup again.")
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
