import SwiftData
import SwiftUI

extension EnvironmentValues {
    @Entry var accentName = "orange"
}

struct CounterView: View {
    @State private var taps = 0
    @State var title = "Counter"
    @Environment(\.accentName) private var accentName

    var body: some View {
        Button("\(title) \(taps) \(accentName)") { taps += 1 }
    }
}

struct NotesView: View {
    @Query(sort: \Note.title) private var notes: [Note]

    var body: some View {
        List(notes) { Text($0.title) }
    }
}

@Animatable
struct Inset: Shape {
    var amount: Double
    @AnimatableIgnored var label = ""

    func path(in rect: CGRect) -> Path { Path(rect.insetBy(dx: amount, dy: amount)) }
}

#Preview("Counter") { CounterView() }

#Preview {
    @Previewable @State var isOn = false
    Toggle("On", isOn: $isOn)
}
