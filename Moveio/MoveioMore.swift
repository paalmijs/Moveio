// Tikai iPHONE target
import SwiftUI
import Combine
import Charts
import HealthKit

// MARK: - Apple Health dati
final class HealthData: ObservableObject {
    private let store = HKHealthStore()
    @Published var authorized = false
    @Published var steps = 0.0
    @Published var energy = 0.0
    @Published var restingHR = 0.0
    @Published var sleep = 0.0
    @Published var weekSteps: [DayStat] = []

    func request() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types: Set<HKObjectType> = [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned),
                                        HKQuantityType(.restingHeartRate), HKCategoryType(.sleepAnalysis)]
        store.requestAuthorization(toShare: [], read: types) { [weak self] ok, _ in
            DispatchQueue.main.async { self?.authorized = ok; if ok { self?.refresh() } }
        }
    }

    func refresh() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        sum(.stepCount, .count(), from: today) { v in DispatchQueue.main.async { self.steps = v } }
        sum(.activeEnergyBurned, .kilocalorie(), from: today) { v in DispatchQueue.main.async { self.energy = v } }

        let hr = HKSampleQuery(sampleType: HKQuantityType(.restingHeartRate), predicate: nil, limit: 1,
                               sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, s, _ in
            let v = (s?.first as? HKQuantitySample)?.quantity.doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
            DispatchQueue.main.async { self.restingHR = v }
        }
        store.execute(hr)

        let from = cal.date(byAdding: .hour, value: -30, to: .now)!
        let sl = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis),
                               predicate: HKQuery.predicateForSamples(withStart: from, end: .now),
                               limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
            let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                    HKCategoryValueSleepAnalysis.asleepREM.rawValue]
            let secs = (s as? [HKCategorySample] ?? []).filter { asleep.contains($0.value) }
                .map { $0.endDate.timeIntervalSince($0.startDate) }.reduce(0, +)
            DispatchQueue.main.async { self.sleep = secs / 3600 }
        }
        store.execute(sl)

        let start = cal.date(byAdding: .day, value: -6, to: today)!
        let q = HKStatisticsCollectionQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: nil,
                                            options: .cumulativeSum, anchorDate: start,
                                            intervalComponents: DateComponents(day: 1))
        q.initialResultsHandler = { _, res, _ in
            var out: [DayStat] = []
            res?.enumerateStatistics(from: start, to: .now) { s, _ in
                out.append(DayStat(date: s.startDate, minutes: s.sumQuantity()?.doubleValue(for: .count()) ?? 0))
            }
            DispatchQueue.main.async { self.weekSteps = out }
        }
        store.execute(q)
    }

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, from: Date, _ done: @escaping (Double) -> Void) {
        let q = HKStatisticsQuery(quantityType: HKQuantityType(id),
                                  quantitySamplePredicate: HKQuery.predicateForSamples(withStart: from, end: .now),
                                  options: .cumulativeSum) { _, s, _ in
            done(s?.sumQuantity()?.doubleValue(for: unit) ?? 0)
        }
        store.execute(q)
    }
}

struct HealthCard: View {
    @StateObject private var h = HealthData()
    var body: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Health").font(.headline)
                    Spacer()
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                }
                if !h.authorized {
                    Button("Connect to Apple Health") {
                        UserDefaults.standard.set(true, forKey: "healthAsked"); h.request()
                    }.buttonStyle(.borderedProminent).tint(.red)
                } else {
                    HStack {
                        metric("figure.walk", "\(Int(h.steps))", "steps", Theme.exercise)
                        metric("bed.double.fill", String(format: "%.1f h", h.sleep), "sleep", Color.indigo)
                        metric("heart.fill", h.restingHR > 0 ? "\(Int(h.restingHR))" : "–", "resting HR", Theme.move)
                        metric("flame.fill", "\(Int(h.energy))", "kcal", Theme.move)
                    }
                    Chart(h.weekSteps) { d in
                        BarMark(x: .value("Day", d.date, unit: .day), y: .value("Steps", d.minutes))
                            .foregroundStyle(Theme.exercise.gradient).cornerRadius(4)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                    .frame(height: 110)
                }
            }
        }
        .onAppear { if UserDefaults.standard.bool(forKey: "healthAsked") { h.request() } }
    }
    func metric(_ icon: String, _ v: String, _ label: String, _ c: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).foregroundStyle(c)
            Text(v).font(.subheadline.weight(.bold)).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

// MARK: - Month calendar
struct CalendarCard: View {
    @EnvironmentObject var conn: ConnectivityManager
    var body: some View {
        let cal = Calendar.current
        let monthStart = cal.dateInterval(of: .month, for: .now)!.start
        let count = cal.range(of: .day, in: .month, for: .now)!.count
        let offset = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let mins = Dictionary(grouping: conn.records, by: { dayKey($0.date) }).mapValues { $0.map(\.duration).reduce(0, +) / 60 }
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text(monthStart.formatted(.dateTime.month(.wide).year())).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 34) }
                    ForEach(1...count, id: \.self) { day in
                        let date = cal.date(byAdding: .day, value: day - 1, to: monthStart)!
                        let m = mins[dayKey(date), default: 0]
                        let isToday = cal.isDateInToday(date)
                        Text("\(day)").font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(m > 0 ? Theme.exercise.opacity(min(0.3 + m / 90, 1)) : Color(.tertiarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isToday ? .white : .clear, lineWidth: 1.5))
                            .foregroundStyle(m > 0 ? Color.black.opacity(0.8) : Color.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Sasniegumi
struct Badge: Identifiable {
    let id = UUID()
    let name: String, desc: String, icon: String
    let color: Color
    let value: Double, goal: Double
    var unlocked: Bool { value >= goal }
}

struct AchievementsView: View {
    @EnvironmentObject var conn: ConnectivityManager

    var longestStreak: Int {
        let cal = Calendar.current
        let days = Set(conn.records.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0, cur = 0
        var prev: Date?
        for d in days {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == d { cur += 1 } else { cur = 1 }
            best = max(best, cur); prev = d
        }
        return best
    }
    func minutes(_ type: String) -> Double { conn.records.filter { $0.type == type }.map(\.duration).reduce(0, +) / 60 }
    func sessions(_ type: String) -> Double { Double(conn.records.filter { $0.type == type }.count) }

    var badges: [Badge] {
        let r = conn.records
        return [
            Badge(name: "First Step", desc: "1 session", icon: "flag.fill", color: Theme.exercise, value: Double(r.count), goal: 1),
            Badge(name: "Regular", desc: "10 sessions", icon: "repeat", color: Theme.exercise, value: Double(r.count), goal: 10),
            Badge(name: "Veteran", desc: "50 sessions", icon: "medal.fill", color: Color.yellow, value: Double(r.count), goal: 50),
            Badge(name: "Week Streak", desc: "7 days in a row", icon: "flame.fill", color: Color.orange, value: Double(longestStreak), goal: 7),
            Badge(name: "Month Streak", desc: "30 days in a row", icon: "flame.circle.fill", color: Theme.move, value: Double(longestStreak), goal: 30),
            Badge(name: "Hour of Motion", desc: "60 min total", icon: "clock.fill", color: Theme.stand, value: r.map(\.duration).reduce(0, +) / 60, goal: 60),
            Badge(name: "10 Hours", desc: "600 min total", icon: "hourglass", color: .blue, value: r.map(\.duration).reduce(0, +) / 60, goal: 600),
            Badge(name: "Thousand", desc: "1000 kcal burned", icon: "bolt.fill", color: Color.yellow, value: r.map(\.calories).reduce(0, +), goal: 1000),
            Badge(name: "10 km", desc: "10 km total", icon: "location.fill", color: Color.orange, value: r.map(\.distance).reduce(0, +) / 1000, goal: 10),
            Badge(name: "Calm Master", desc: "60 min meditating", icon: "leaf.fill", color: Color.mint, value: minutes("Meditation"), goal: 60),
            Badge(name: "Focus Master", desc: "10 pomodoros", icon: "timer", color: Theme.move, value: sessions("Pomodoro"), goal: 10),
            Badge(name: "Flexible", desc: "5 stretching sessions", icon: "figure.flexibility", color: Color.purple, value: sessions("Stretching"), goal: 5),
        ]
    }

    var body: some View {
        ScrollView {
            Text("\(badges.filter(\.unlocked).count) / \(badges.count) unlocked")
                .font(.subheadline).foregroundStyle(.secondary).padding(.top)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(badges) { b in
                    VStack(spacing: 8) {
                        Image(systemName: b.icon).font(.system(size: 34))
                            .foregroundStyle(b.unlocked ? b.color : Color.gray.opacity(0.5))
                        Text(b.name).font(.subheadline.weight(.bold))
                        Text(b.desc).font(.caption2).foregroundStyle(.secondary)
                        ProgressView(value: min(b.value, b.goal), total: b.goal).tint(b.color)
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(b.unlocked ? b.color.opacity(0.12) : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 18))
                    .opacity(b.unlocked ? 1 : 0.75)
                }
            }.padding()
        }
        .navigationTitle("Achievements")
    }
}

// MARK: - Manual log and export
func csvText(_ r: [WorkoutRecord]) -> String {
    var s = "date,type,minutes,kcal,avg_hr,km\n"
    let f = ISO8601DateFormatter()
    for x in r {
        s += "\(f.string(from: x.date)),\(x.type),\(Int(x.duration / 60)),\(Int(x.calories)),\(Int(x.avgHeartRate)),\(String(format: "%.2f", x.distance / 1000))\n"
    }
    return s
}

struct ManualLogView: View {
    @EnvironmentObject var conn: ConnectivityManager
    @Environment(\.dismiss) private var dismiss
    @State private var type = "Running"
    @State private var date = Date()
    @State private var minutes = 30
    @State private var kcal = 0
    @State private var km = 0.0
    let types = ["Running", "Walking", "Cycling", "Strength", "HIIT", "Yoga", "Swimming", "Meditation", "Stretching", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) { ForEach(types, id: \.self) { Text($0) } }
                DatePicker("Date", selection: $date, in: ...Date())
                Stepper("Duration: \(minutes) min", value: $minutes, in: 5...300, step: 5)
                Stepper("Calories: \(kcal) kcal", value: $kcal, in: 0...3000, step: 10)
                Stepper(String(format: "Distance: %.1f km", km), value: $km, in: 0...100, step: 0.5)
            }
            .navigationTitle("New workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        conn.add(WorkoutRecord(type: type, date: date, duration: Double(minutes) * 60,
                                               calories: Double(kcal), avgHeartRate: 0, distance: km * 1000))
                        dismiss()
                    }
                }
            }
        }
    }
}
