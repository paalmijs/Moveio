// Add to the MoveioWidget extension target ONLY (delete the files Xcode generated there)
import WidgetKit
import SwiftUI

// MARK: - Timeline
struct StreakEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry { StreakEntry(date: .now, snap: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: .now, snap: context.isPreview ? .sample : (SharedStore.load() ?? .empty)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let snap = SharedStore.load() ?? .empty
        let now = Date()
        // A second entry right after midnight, so the flame turns gray if you haven't moved yet today.
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400)).addingTimeInterval(5)
        let entries = [StreakEntry(date: now, snap: snap), StreakEntry(date: midnight, snap: snap)]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(3600))))
    }
}

// MARK: - Views
struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    private var snap: WidgetSnapshot { entry.snap }
    private var streak: Int { snap.streak(now: entry.date) }
    private var done: Bool { snap.doneToday(now: entry.date) }
    private let flameColors: [Color] = [Color(red: 1, green: 0.85, blue: 0.2), .orange, Color(red: 1, green: 0.25, blue: 0.2)]

    var body: some View {
        switch family {
        case .systemMedium: medium.containerBackground(for: .widget) { background }
        case .accessoryCircular: circular.containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular: rectangular.containerBackground(for: .widget) { Color.clear }
        default: small.containerBackground(for: .widget) { background }
        }
    }

    private var background: some View {
        ZStack {
            Color(.systemBackground)
            if done { Color.orange.opacity(0.10) }
        }
    }

    private func flame(_ size: CGFloat) -> some View {
        Image(systemName: "flame.fill")
            .font(.system(size: size))
            .foregroundStyle(done
                ? AnyShapeStyle(LinearGradient(colors: flameColors, startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(Color.gray.opacity(0.45)))
            .shadow(color: done ? .orange.opacity(0.45) : .clear, radius: 8)
    }

    private var caption: String {
        if streak == 0 && !done { return "Start your streak" }
        return done ? "Done for today" : "Move to keep it!"
    }

    // Home screen: small
    private var small: some View {
        VStack(spacing: 2) {
            flame(46)
            Text("\(streak)")
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(done ? Color.orange : Color.primary)
                .contentTransition(.numericText())
            Text(streak == 1 ? "day streak" : "day streak")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(caption).font(.caption2).foregroundStyle(done ? .orange : .secondary).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Home screen: medium
    private var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 0) {
                flame(46)
                Text("\(streak)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(done ? Color.orange : Color.primary)
                Text("day streak").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(width: 104)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(Array(snap.week(now: entry.date).enumerated()), id: \.offset) { _, d in
                        dayDot(d.date, d.done).frame(maxWidth: .infinity)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: min(Double(snap.weekMinutes(now: entry.date)) / Double(max(snap.weeklyGoal, 1)), 1))
                        .tint(.orange)
                    Text("\(snap.weekMinutes(now: entry.date)) / \(snap.weeklyGoal) min this week")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(caption).font(.caption.weight(.semibold)).foregroundStyle(done ? .orange : .secondary)
            }
        }
    }

    private func dayDot(_ date: Date, _ active: Bool) -> some View {
        let isToday = Calendar.current.isDate(date, inSameDayAs: entry.date)
        return VStack(spacing: 4) {
            Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
            ZStack {
                Circle().fill(active ? Color.orange : Color.gray.opacity(0.2))
                if active { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                if isToday && !active { Circle().stroke(Color.orange, lineWidth: 1.5) }
            }
            .frame(width: 22, height: 22)
        }
    }

    // Lock screen
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill").font(.system(size: 16))
                Text("\(streak)").font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .opacity(done ? 1 : 0.6)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(streak) day streak", systemImage: "flame.fill").font(.headline)
            Text(done ? "Done for today" : "Move to keep it!").font(.caption)
            Text("\(snap.weekMinutes(now: entry.date)) / \(snap.weeklyGoal) min this week").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget
struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoveioStreakWidget", provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Keep your daily workout streak alive.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct MoveioWidgets: WidgetBundle {
    var body: some Widget { StreakWidget() }
}
