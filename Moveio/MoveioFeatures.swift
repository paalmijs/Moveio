// iPhone target only
import SwiftUI
import Combine
import Charts
import UIKit
import UserNotifications

// MARK: - Helpers
func clock(_ t: TimeInterval) -> String {
    let s = Int(t.rounded(.up)); return String(format: "%02d:%02d", s / 60, s % 60)
}
func dayKey(_ d: Date = .now) -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
}
func phoneLog(_ type: String, _ duration: TimeInterval) {
    ConnectivityManager.shared.add(WorkoutRecord(type: type, date: .now, duration: duration,
                                                 calories: 0, avgHeartRate: 0, distance: 0))
}
func haptic() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
func ud(_ k: String, _ def: Int) -> Int { (UserDefaults.standard.object(forKey: k) as? Int) ?? def }

final class PhoneTimer: ObservableObject {
    @Published var remaining: TimeInterval = 0
    @Published var total: TimeInterval = 0
    @Published var running = false
    var onFinish: (() -> Void)?
    private var end: Date?
    private var timer: Timer?

    func start(_ s: TimeInterval, notify: String? = nil) {
        total = s; remaining = s
        end = Date().addingTimeInterval(s); running = true
        if let notify {
            let c = UNUserNotificationCenter.current()
            c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
                guard ok else { return }
                let content = UNMutableNotificationContent()
                content.title = notify; content.sound = .default
                c.add(UNNotificationRequest(identifier: "phoneTimer", content: content,
                      trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, s), repeats: false)))
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
    }
    private func tick() {
        guard let end else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { stop(cancel: false); haptic(); onFinish?() }
    }
    func stop(cancel: Bool = true) {
        timer?.invalidate(); timer = nil; running = false; end = nil
        if cancel { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["phoneTimer"]) }
    }
}

// MARK: - Tools
struct ToolsView: View {
    var body: some View {
        NavigationStack {
            List {
                row("Meditation", "Breathing and calm", "leaf.fill", .mint) { PhoneMeditation() }
                row("Pomodoro", "Focus 25 / break 5", "timer", .orange) { PhonePomodoro() }
                row("Stretching", "Guided routine", "figure.flexibility", .purple) { PhoneStretch() }
                row("Water", "Daily water tracker", "drop.fill", Theme.stand) { WaterView() }
                row("Plans", "Training plans with progress", "list.bullet.clipboard.fill", Theme.move) { PlansView(embedded: true) }
            }
            .navigationTitle("Tools")
        }
    }
    func row<D: View>(_ t: String, _ sub: String, _ icon: String, _ c: Color,
                      @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(c.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading) {
                    Text(t).font(.headline)
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 4)
        }
    }
}

// MARK: - Meditation
struct PhoneMeditation: View {
    @StateObject private var t = PhoneTimer()
    @State private var minutes = 5
    @State private var started = false
    @State private var finished = false
    @State private var inhale = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            if finished {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 80)).foregroundStyle(.mint)
                Text("Well done!").font(.title2.bold())
                Button("Again") { finished = false }.buttonStyle(.borderedProminent).tint(.mint)
            } else if started {
                ZStack {
                    Circle().fill(.mint.opacity(0.3)).scaleEffect(inhale ? 1 : 0.5)
                    Circle().stroke(.mint, lineWidth: 3).scaleEffect(inhale ? 1 : 0.5)
                    Text(inhale ? "Inhale" : "Exhale").font(.title3.weight(.medium))
                }
                .frame(width: 260, height: 260)
                .animation(.easeInOut(duration: 4), value: inhale)
                Text(clock(t.remaining)).font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                Button("End") { end() }.tint(.red).buttonStyle(.bordered)
            } else {
                Image(systemName: "leaf.fill").font(.system(size: 60)).foregroundStyle(.mint)
                HStack {
                    ForEach([1, 3, 5, 10, 15], id: \.self) { m in
                        Button("\(m)") { minutes = m }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(minutes == m ? Color.mint : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(minutes == m ? Color.black : Color.primary)
                    }
                }
                Text("minutes").foregroundStyle(.secondary)
                Button("Start") { begin() }.buttonStyle(.borderedProminent).tint(.mint).controlSize(.large)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("Meditation")
        .task(id: started) {
            guard started else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                inhale.toggle()
            }
        }
        .onDisappear { t.stop(); UIApplication.shared.isIdleTimerDisabled = false }
    }

    func begin() {
        UIApplication.shared.isIdleTimerDisabled = true
        t.onFinish = {
            phoneLog("Meditation", Double(minutes) * 60)
            started = false; finished = true
            UIApplication.shared.isIdleTimerDisabled = false
        }
        t.start(Double(minutes) * 60, notify: "Meditation complete 🍃")
        started = true; inhale = true
    }
    func end() {
        t.stop(); started = false
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

// MARK: - Pomodoro
struct PhonePomodoro: View {
    enum Phase { case focus, short, long }
    @StateObject private var t = PhoneTimer()
    @State private var phase: Phase = .focus
    @State private var count = 0

    var length: TimeInterval {
        switch phase {
        case .focus: return 25 * 60
        case .short: return 5 * 60
        case .long: return 15 * 60
        }
    }
    var title: String {
        switch phase {
        case .focus: return "Focus"
        case .short: return "Short break"
        case .long: return "Long break"
        }
    }
    var color: Color { phase == .focus ? Theme.move : Theme.exercise }
    var progress: Double { t.running && t.total > 0 ? 1 - t.remaining / t.total : 0 }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(color)
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 16)
                Circle().trim(from: 0, to: progress)
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(clock(t.running ? t.remaining : length))
                    .font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(width: 260, height: 260)
            HStack(spacing: 16) {
                Button(t.running ? "Stop" : "Start") {
                    if t.running { t.stop() }
                    else { t.start(length, notify: phase == .focus ? "Time for a break ☕️" : "Back to work 🍅") }
                }.buttonStyle(.borderedProminent).tint(color).controlSize(.large)
                Button("Skip") { t.stop(); next(log: false) }.buttonStyle(.bordered)
            }
            Text("🍅 × \(count)").font(.title3)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("Pomodoro")
        .onAppear { t.onFinish = { next(log: true) } }
        .onDisappear { t.stop() }
    }

    func next(log: Bool) {
        if phase == .focus {
            if log { count += 1; phoneLog("Pomodoro", 25 * 60) }
            phase = (count > 0 && count % 4 == 0) ? .long : .short
        } else { phase = .focus }
    }
}

// MARK: - Stretching
struct PhoneStep: Identifiable {
    let id = UUID()
    let name: String, hint: String, icon: String, seconds: TimeInterval
}
let phoneStretch = [
    PhoneStep(name: "Neck", hint: "Slowly tilt your head to the side", icon: "figure.mind.and.body", seconds: 30),
    PhoneStep(name: "Shoulders", hint: "Roll your shoulders slowly backward", icon: "figure.arms.open", seconds: 30),
    PhoneStep(name: "Arms", hint: "Reach both arms overhead", icon: "figure.stand", seconds: 30),
    PhoneStep(name: "Back", hint: "Fold forward and relax", icon: "figure.cooldown", seconds: 30),
    PhoneStep(name: "Hips", hint: "Deep lunge, hold the pose", icon: "figure.flexibility", seconds: 30),
    PhoneStep(name: "Calves", hint: "Lean on a wall, one leg back", icon: "figure.yoga", seconds: 30),
]

struct PhoneStretch: View {
    @StateObject private var t = PhoneTimer()
    @State private var idx = 0
    @State private var started = false
    @State private var finished = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if finished {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 80)).foregroundStyle(.purple)
                Text("All done!").font(.title2.bold())
                Button("Again") { finished = false }.buttonStyle(.borderedProminent).tint(.purple)
            } else if started {
                let s = phoneStretch[idx]
                Text("\(idx + 1) / \(phoneStretch.count)").foregroundStyle(.secondary)
                Image(systemName: s.icon).font(.system(size: 90)).foregroundStyle(.purple)
                Text(s.name).font(.largeTitle.bold())
                Text(s.hint).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                Text(clock(t.remaining)).font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                Button("Skip") { t.stop(); advance() }.buttonStyle(.bordered)
            } else {
                Image(systemName: "figure.flexibility").font(.system(size: 80)).foregroundStyle(.purple)
                Text("\(phoneStretch.count) exercises · \(Int(phoneStretch.map(\.seconds).reduce(0, +) / 60)) min")
                Button("Start") { idx = 0; started = true; run() }
                    .buttonStyle(.borderedProminent).tint(.purple).controlSize(.large)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("Stretching")
        .onAppear { t.onFinish = { advance() } }
        .onDisappear { t.stop() }
    }

    func run() { t.start(phoneStretch[idx].seconds) }
    func advance() {
        if idx + 1 < phoneStretch.count { idx += 1; run() }
        else {
            phoneLog("Stretching", phoneStretch.map(\.seconds).reduce(0, +))
            started = false; finished = true
        }
    }
}

// MARK: - Water
final class WaterStore: ObservableObject {
    @Published var log: [String: Int] = [:]
    private let key = "waterLog"
    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let l = try? JSONDecoder().decode([String: Int].self, from: d) { log = l }
    }
    var today: Int { log[dayKey(), default: 0] }
    func add(_ ml: Int) {
        log[dayKey()] = max(0, today + ml)
        if let d = try? JSONEncoder().encode(log) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct WaterView: View {
    @StateObject private var store = WaterStore()
    @AppStorage("waterGoal") private var goal = 2000
    var week: [DayStat] {
        (0..<7).reversed().map { i in
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Calendar.current.startOfDay(for: .now))!
            return DayStat(date: d, minutes: Double(store.log[dayKey(d), default: 0]))
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    AnimatedRing(progress: Double(store.today) / Double(goal), color: Theme.stand, lineWidth: 18)
                    VStack {
                        Image(systemName: "drop.fill").foregroundStyle(Theme.stand)
                        Text("\(store.today) ml").font(.system(size: 34, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("goal \(goal) ml").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 220, height: 220).padding(.top)
                HStack(spacing: 12) {
                    ForEach([150, 250, 500], id: \.self) { ml in
                        Button("+\(ml)") { withAnimation(.spring) { store.add(ml) } }
                            .buttonStyle(.borderedProminent).tint(Theme.stand).controlSize(.large)
                    }
                    Button { withAnimation(.spring) { store.add(-250) } } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.bordered)
                }
                card {
                    VStack(alignment: .leading) {
                        Text("Last 7 days").font(.headline)
                        Chart(week) { d in
                            BarMark(x: .value("Day", d.date, unit: .day), y: .value("ml", d.minutes))
                                .foregroundStyle(Theme.stand.gradient).cornerRadius(5)
                            RuleMark(y: .value("Goal", goal)).foregroundStyle(.secondary.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                        .frame(height: 140)
                    }
                }
                Stepper("Goal: \(goal) ml", value: $goal, in: 500...5000, step: 250).padding(.horizontal)
            }.padding()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Water")
    }
}

// MARK: - Body measurements
struct BodyEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var weight: Double
    var waist: Double?
}

final class BodyStore: ObservableObject {
    @Published var entries: [BodyEntry] = []
    private let key = "bodyEntries"
    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let e = try? JSONDecoder().decode([BodyEntry].self, from: d) { entries = e }
    }
    func add(_ e: BodyEntry) { entries.insert(e, at: 0); entries.sort { $0.date > $1.date }; save() }
    func remove(_ offsets: IndexSet) { entries.remove(atOffsets: offsets); save() }
    private func save() {
        if let d = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct BodyView: View {
    @StateObject private var store = BodyStore()
    @State private var weightText = ""
    @State private var waistText = ""

    func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        Form {
            Section("New measurement") {
                TextField("Weight, kg", text: $weightText).keyboardType(.decimalPad)
                TextField("Waist, cm (optional)", text: $waistText).keyboardType(.decimalPad)
                Button("Save") {
                    if let w = num(weightText) {
                        store.add(BodyEntry(date: .now, weight: w, waist: num(waistText)))
                        weightText = ""; waistText = ""
                    }
                }.disabled(num(weightText) == nil)
            }
            if store.entries.count > 1 {
                Section("Weight change") {
                    let sorted = store.entries.sorted { $0.date < $1.date }
                    let diff = (sorted.last?.weight ?? 0) - (sorted.first?.weight ?? 0)
                    Text(String(format: "%+.1f kg since first entry", diff))
                        .foregroundStyle(diff <= 0 ? Theme.exercise : Color.orange)
                    Chart(sorted) { e in
                        LineMark(x: .value("Date", e.date), y: .value("kg", e.weight)).foregroundStyle(Theme.move)
                        PointMark(x: .value("Date", e.date), y: .value("kg", e.weight)).foregroundStyle(Theme.move)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                }
            }
            Section("History") {
                ForEach(store.entries) { e in
                    HStack {
                        Text(e.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(String(format: "%.1f kg", e.weight)).bold()
                        if let w = e.waist { Text(String(format: "· %.0f cm", w)).foregroundStyle(.secondary) }
                    }
                }.onDelete(perform: store.remove)
            }
        }
        .navigationTitle("Body")
    }
}

// MARK: - Training plans
struct Plan: Identifiable {
    let id: String, name: String, subtitle: String, icon: String
    let color: Color
    let weeks: [[String]]
}

let plans: [Plan] = [
    Plan(id: "run", name: "Start Running", subtitle: "4 weeks · 3 workouts per week", icon: "figure.run", color: Theme.move, weeks: [
        ["Run 1 min / walk 2 min × 8", "Run 1 min / walk 2 min × 8", "Run 2 min / walk 2 min × 6"],
        ["Run 3 min / walk 2 min × 5", "Run 3 min / walk 2 min × 5", "Run 5 min / walk 2 min × 4"],
        ["Run 8 min / walk 2 min × 3", "Run 10 min / walk 2 min × 2", "Run 12 min nonstop"],
        ["Run 15 min nonstop", "Run 18 min nonstop", "Run 20 min nonstop 🎉"],
    ]),
    Plan(id: "strength", name: "Strength at Home", subtitle: "4 weeks · no equipment", icon: "dumbbell.fill", color: .orange,
         weeks: [2, 3, 3, 4].map { n in [
            "Day A: squats, push-ups, plank · \(n) sets",
            "Day B: lunges, glute bridge, superman · \(n) sets",
            "Day C: A + B circuit · \(n) rounds",
         ] }),
    Plan(id: "mobility", name: "Mobility", subtitle: "2 weeks · 4 sessions per week", icon: "figure.flexibility", color: .purple, weeks: [
        ["Morning stretch 10 min", "Neck and shoulders 5 min", "Back and hips 10 min", "Full-body routine 10 min"],
        ["Morning stretch 15 min", "Neck and shoulders 10 min", "Back and hips 15 min", "Full-body routine 15 min"],
    ]),
]

final class PlanProgress: ObservableObject {
    @Published var done: Set<String> = []
    private let key = "planDone"
    init() { done = Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    func toggle(_ id: String) {
        if done.contains(id) { done.remove(id) } else { done.insert(id); haptic() }
        UserDefaults.standard.set(Array(done), forKey: key)
    }
    func count(_ p: Plan) -> Int { done.filter { $0.hasPrefix(p.id + "-") }.count }
}

struct PlansView: View {
    var embedded = false
    @StateObject private var progress = PlanProgress()
    var body: some View {
        if embedded { list } else { NavigationStack { list } }
    }
    var list: some View {
        List(plans) { p in
            NavigationLink { PlanDetail(plan: p, progress: progress) } label: {
                HStack(spacing: 14) {
                    Image(systemName: p.icon).font(.body.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 38, height: 38).background(p.color.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.name).font(.headline)
                        Text(p.subtitle).font(.caption).foregroundStyle(.secondary)
                        let total = p.weeks.flatMap { $0 }.count
                        ProgressView(value: Double(progress.count(p)), total: Double(total)).tint(p.color)
                    }
                }.padding(.vertical, 6)
            }
        }
        .navigationTitle("Plans")
    }
}

struct PlanDetail: View {
    let plan: Plan
    @ObservedObject var progress: PlanProgress
    var body: some View {
        List {
            ForEach(Array(plan.weeks.enumerated()), id: \.offset) { w, sessions in
                Section("Week \(w + 1)") {
                    ForEach(Array(sessions.enumerated()), id: \.offset) { d, text in
                        let id = "\(plan.id)-\(w)-\(d)"
                        Button { withAnimation(.spring) { progress.toggle(id) } } label: {
                            HStack {
                                Image(systemName: progress.done.contains(id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(progress.done.contains(id) ? plan.color : Color.secondary)
                                    .symbolEffect(.bounce, value: progress.done.contains(id))
                                Text(text).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            }
                        }
                    }
                }
            }
        }
        .confetti(trigger: progress.count(plan) == plan.weeks.flatMap { $0 }.count)
        .navigationTitle(plan.name)
    }
}

// MARK: - Reminders
func rescheduleReminders() {
    let c = UNUserNotificationCenter.current()
    c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
        guard ok else { return }
        c.getPendingNotificationRequests { reqs in
            c.removePendingNotificationRequests(withIdentifiers: reqs.map(\.identifier).filter { $0.hasPrefix("rem-") })
            let d = UserDefaults.standard
            func add(_ id: String, _ title: String, _ body: String, _ comps: DateComponents) {
                let n = UNMutableNotificationContent()
                n.title = title; n.body = body; n.sound = .default
                c.add(UNNotificationRequest(identifier: id, content: n,
                      trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
            }
            if d.bool(forKey: "remWorkout") {
                let m = ud("remWorkoutMin", 18 * 60), mask = ud("remDays", 84)
                for wd in 1...7 where mask & (1 << wd) != 0 {
                    add("rem-workout-\(wd)", "Workout time 💪", "Moveio is waiting. Start today's workout!",
                        DateComponents(hour: m / 60, minute: m % 60, weekday: wd))
                }
            }
            if d.bool(forKey: "remMove") {
                let every = max(1, ud("remMoveEvery", 2))
                for h in stride(from: 9, through: 20, by: every) {
                    add("rem-move-\(h)", "Time to move 🚶", "Stand up, stretch or walk for a couple of minutes.",
                        DateComponents(hour: h, minute: 0))
                }
            }
            if d.bool(forKey: "remWater") {
                for h in stride(from: 10, through: 20, by: 2) {
                    add("rem-water-\(h)", "Drink water 💧", "Don't forget to top up your water.",
                        DateComponents(hour: h, minute: 30))
                }
            }
        }
    }
}

struct RemindersView: View {
    @AppStorage("remWorkout") private var workoutOn = false
    @AppStorage("remWorkoutMin") private var workoutMin = 18 * 60
    @AppStorage("remDays") private var days = 84
    @AppStorage("remMove") private var moveOn = false
    @AppStorage("remMoveEvery") private var moveEvery = 2
    @AppStorage("remWater") private var waterOn = false

    var sig: [Int] { [workoutOn ? 1 : 0, workoutMin, days, moveOn ? 1 : 0, moveEvery, waterOn ? 1 : 0] }
    let dayNames = [(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")]

    var timeBinding: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: workoutMin / 60, minute: workoutMin % 60, second: 0, of: .now)! },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                       workoutMin = (c.hour ?? 18) * 60 + (c.minute ?? 0) })
    }

    var body: some View {
        Form {
            Section("Workout") {
                Toggle("Remind me to work out", isOn: $workoutOn)
                if workoutOn {
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    HStack {
                        ForEach(dayNames, id: \.0) { wd, name in
                            let on = days & (1 << wd) != 0
                            Button(name) { days ^= (1 << wd) }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(on ? Theme.exercise : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(on ? Color.black : Color.primary)
                        }
                    }.buttonStyle(.plain)
                }
            }
            Section("Movement") {
                Toggle("Remind me to move (9:00–20:00)", isOn: $moveOn)
                if moveOn { Stepper("Every \(moveEvery) h", value: $moveEvery, in: 1...4) }
            }
            Section("Water") {
                Toggle("Remind me to drink water (every 2 h)", isOn: $waterOn)
            }
        }
        .navigationTitle("Reminders")
        .onChange(of: sig) { rescheduleReminders() }
    }
}
