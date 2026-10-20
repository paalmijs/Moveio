// Moveio (iPhone app) target ONLY
import Foundation
import WidgetKit

/// Copies what the widget needs into the shared App Group and asks iOS to refresh the widgets.
enum WidgetSync {
    static func push(_ records: [WorkoutRecord]) {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -400, to: .now)!.timeIntervalSince1970
        var perDay: [Double: Double] = [:]
        for r in records {
            let d = cal.startOfDay(for: r.date).timeIntervalSince1970
            if d >= cutoff { perDay[d, default: 0] += r.duration / 60 }
        }
        let days = perDay.map { DayEntry(day: $0.key, minutes: $0.value) }.sorted { $0.day < $1.day }
        let goal = (UserDefaults.standard.object(forKey: "weeklyGoal") as? Int) ?? 150
        SharedStore.save(WidgetSnapshot(days: days, weeklyGoal: goal, name: ProfileStore.shared.name))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
