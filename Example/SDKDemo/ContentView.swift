import SwiftUI
import Foundation

/// Compiles only against the macOS 27 SDK: ProgressManager is new in macOS 27.
/// On older systems the availability check skips it at runtime.
func sdk27Probe() -> String {
    if #available(macOS 27, *) {
        let manager = ProgressManager(totalCount: 4)
        return "macOS 27 API available, total: \(manager.totalCount ?? 0)"
    }
    return "Built with SDK 27; running on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Newer SDK on an Intel Mac")
                .font(.title)
            Text(sdk27Probe())
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

#Preview {
    ContentView()
}
