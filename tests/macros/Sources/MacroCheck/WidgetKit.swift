import SwiftUI
import WidgetKit

struct ClockEntry: TimelineEntry {
    let date: Date
}

struct ClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClockEntry { ClockEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (ClockEntry) -> Void) {
        completion(ClockEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClockEntry>) -> Void) {
        completion(Timeline(entries: [ClockEntry(date: .now)], policy: .never))
    }
}

struct ClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "clock", provider: ClockProvider()) { entry in
            Text(entry.date, style: .time)
        }
    }
}

#Preview(as: .systemSmall) {
    ClockWidget()
} timeline: {
    ClockEntry(date: .now)
}
