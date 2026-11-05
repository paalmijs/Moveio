// Add to BOTH: Moveio (iPhone app) target AND the MoveioWidget extension target
import Foundation

enum SharedStore {
    /// Must be EXACTLY the App Group you add in Signing & Capabilities (iPhone app AND widget).
    static let group = "group.palmijs.Moveio"
    static let key = "widgetSnapshot"

    private static var defaults: UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil else {
            return nil
        }
        return UserDefaults(suiteName: group)
    }

    @discardableResult
    static func save(_ s: WidgetSnapshot) -> Bool {
        guard let defaults, let d = try? JSONEncoder().encode(s) else { return false }
        defaults.set(d, forKey: key)
        return true
    }
    static func load() -> WidgetSnapshot? {
        guard let d = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }
}

struct DayEntry: Codable {
    var day: Double          // start of day, seconds since 1970
    var minutes: Double
}

struct WidgetSnapshot: Codable {
    var days: [DayEntry]     // only days that have at least one session
    var weeklyGoal: Int
    var name: String

    static let empty = WidgetSnapshot(days: [], weeklyGoal: 150, name: "")

    /// Fake data for the widget gallery.
    static var sample: WidgetSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = [0, 1, 2, 3, 4, 6].map { i -> DayEntry in
            DayEntry(day: cal.date(byAdding: .day, value: -i, to: today)!.timeIntervalSince1970, minutes: Double(20 + i * 5))
        }
        return WidgetSnapshot(days: days, weeklyGoal: 150, name: "")
    }

    private var active: Set<Double> { Set(days.map(\.day)) }

    func doneToday(now: Date = .now) -> Bool {
        active.contains(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
    }

    /// Consecutive days ending today, or yesterday if today isn't done yet.
    func streak(now: Date = .now) -> Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: now)
        if !active.contains(day.timeIntervalSince1970) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while active.contains(day.timeIntervalSince1970) {
            n += 1; day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    /// The last 7 days, oldest first.
    func week(now: Date = .now) -> [(date: Date, done: Bool)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return (0..<7).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            return (d, active.contains(d.timeIntervalSince1970))
        }
    }

    func weekMinutes(now: Date = .now) -> Int {
        let from = week(now: now).first!.date.timeIntervalSince1970
        return Int(days.filter { $0.day >= from }.map(\.minutes).reduce(0, +))
    }
}
