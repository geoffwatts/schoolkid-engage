import WidgetKit
import SwiftUI
import LMSKit

@main
struct SchoolkidWidgets: WidgetBundle {
    var body: some Widget { SchoolDayWidget() }
}

/// Today's cycle day (with Week A/B at fortnightly schools) and the lesson now or next.
struct SchoolDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SchoolDay", provider: SchoolDayProvider()) { entry in
            SchoolDayView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
                // It's a timetable widget, so a tap opens the timetable on the day it describes.
                .widgetURL(URL(string: "schoolkidengage://timetable"))
        }
        .configurationDisplayName("School day")
        .description("Today's cycle day and the next lesson.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}

struct SchoolDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> SchoolDayEntry { SchoolDayEntry(date: .now, snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (SchoolDayEntry) -> Void) {
        completion(SchoolDayEntry(date: .now, snapshot: WidgetSnapshot.load() ?? (context.isPreview ? .sample : nil)))
    }
    /// One entry now, then one at every lesson start and end over the next day and a half, plus midnight, so "now" and
    /// "next" roll over on time without the app running.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SchoolDayEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load(), now = Date(), horizon = now.addingTimeInterval(36 * 3600)
        var dates: Set<Date> = [now, Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))]
        for lesson in snapshot?.lessons ?? [] {
            for moment in [lesson.start, lesson.end] where moment > now && moment < horizon { dates.insert(moment) }
        }
        completion(Timeline(entries: dates.sorted().map { SchoolDayEntry(date: $0, snapshot: snapshot) }, policy: .after(horizon)))
    }
}
