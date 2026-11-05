import SwiftUI
import HealthKit
import Combine
import WatchKit

// Fitness Clean ring colors
extension Color {
    static let moveRed = Color(red: 0.98, green: 0.07, blue: 0.31)
    static let exerciseGreen = Color(red: 0.65, green: 0.95, blue: 0.0)
    static let standCyan = Color(red: 0.0, green: 0.82, blue: 0.98)
}

// MARK: - Workout manager
final class WorkoutManager: NSObject, ObservableObject {
    let store = HKHealthStore()
    @Published var session: HKWorkoutSession?
    var builder: HKLiveWorkoutBuilder?
    var timer: Timer?

    @Published var running = false
    @Published var heartRate = 0.0
    @Published var calories = 0.0
    @Published var distance = 0.0
    @Published var elapsed: TimeInterval = 0
    @Published var summary: WorkoutRecord?
    var name = "Running"

    static let shared = WorkoutManager()

    static func name(for t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "Yoga"
        case .swimming: return "Swimming"
        default: return "Other"
        }
    }

    /// Called when a workout is started from the iPhone app.
    func startFromPhone(_ cfg: HKWorkoutConfiguration) {
        guard session == nil else { return }
        requestAuth()
        start(cfg.activityType, name: Self.name(for: cfg.activityType))
    }

    func requestAuth() {
        let share: Set = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)
        ]
        store.requestAuthorization(toShare: share, read: read) { _, _ in }
    }

    func start(_ type: HKWorkoutActivityType, name: String) {
        self.name = name
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = type
        cfg.locationType = (type == .running || type == .cycling || type == .walking) ? .outdoor : .indoor
        do {
            session = try HKWorkoutSession(healthStore: store, configuration: cfg)
            builder = session?.associatedWorkoutBuilder()
        } catch { return }
        session?.delegate = self
        builder?.delegate = self
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: cfg)
        let date = Date()
        session?.startActivity(with: date)
        builder?.beginCollection(withStart: date) { _, _ in }
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.elapsed = self?.builder?.elapsedTime ?? 0 }
        }
    }

    func togglePause() { running ? session?.pause() : session?.resume() }

    func end() {
        session?.end()
        timer?.invalidate()
    }

    private func finish(date: Date) {
        builder?.endCollection(withEnd: date) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let r = WorkoutRecord(type: self.name, date: date, duration: self.elapsed,
                                          calories: self.calories,
                                          avgHeartRate: self.builder?.statistics(for: HKQuantityType(.heartRate))?
                                            .averageQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) ?? 0,
                                          distance: self.distance)
                    ConnectivityManager.shared.add(r)
                    self.summary = r
                }
            }
        }
    }

    func reset() {
        summary = nil; heartRate = 0; calories = 0; distance = 0; elapsed = 0
        session = nil; builder = nil
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState,
                        from: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { self.running = (to == .running) }
        if to == .ended { finish(date: date) }
    }
    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}
    func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        for t in types {
            guard let q = t as? HKQuantityType, let st = b.statistics(for: q) else { continue }
            DispatchQueue.main.async {
                switch q {
                case HKQuantityType(.heartRate):
                    self.heartRate = st.mostRecentQuantity()?
                        .doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
                case HKQuantityType(.activeEnergyBurned):
                    self.calories = st.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                case HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling):
                    self.distance = st.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                default: break
                }
            }
        }
    }
}

// MARK: - App entry point
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    // The iPhone app asks the Watch to start a workout
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        DispatchQueue.main.async { WorkoutManager.shared.startFromPhone(workoutConfiguration) }
    }
}

@main
struct MoveioWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var delegate
    @StateObject var manager = WorkoutManager.shared
    var body: some Scene {
        WindowGroup {
            NavigationStack { HomeView() }
                .environmentObject(manager)
                // One place that shows the live workout and the summary, wherever it was started
                .fullScreenCover(isPresented: Binding(get: { manager.session != nil }, set: { _ in })) {
                    NavigationStack {
                        if manager.summary != nil { SummaryView() } else { SessionView() }
                    }
                    .environmentObject(manager)
                }
                .onAppear {
                    manager.requestAuth()
                    ConnectivityManager.shared.start()
                }
        }
    }
}

struct Sport: Identifiable {
    let id = UUID()
    let name: String, icon: String, type: HKWorkoutActivityType, color: Color
}
let sports = [
    Sport(name: "Running", icon: "figure.run", type: .running, color: .moveRed),
    Sport(name: "Walking", icon: "figure.walk", type: .walking, color: .exerciseGreen),
    Sport(name: "Cycling", icon: "figure.outdoor.cycle", type: .cycling, color: .standCyan),
    Sport(name: "Strength", icon: "dumbbell.fill", type: .traditionalStrengthTraining, color: .orange),
    Sport(name: "HIIT", icon: "flame.fill", type: .highIntensityIntervalTraining, color: .red),
]

struct StartView: View {
    @EnvironmentObject var m: WorkoutManager
    var body: some View {
        List(sports) { s in
            Button { m.start(s.type, name: s.name) } label: {
                HStack(spacing: 12) {
                    Image(systemName: s.icon).font(.body.weight(.semibold)).foregroundStyle(.black)
                        .frame(width: 34, height: 34).background(s.color, in: Circle())
                    Text(s.name).font(.headline)
                }.padding(.vertical, 4)
            }
            .listItemTint(s.color.opacity(0.22))
        }
        .navigationTitle("Workout")
    }
}

func fmt(_ t: TimeInterval) -> String {
    let s = Int(t); return String(format: "%02d:%02d:%02d", s/3600, (s/60)%60, s%60)
}

struct SessionView: View {
    @EnvironmentObject var m: WorkoutManager
    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: 4) {
                Text(fmt(m.elapsed)).font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.yellow).monospacedDigit()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(m.heartRate))").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Image(systemName: "heart.fill").foregroundStyle(Color.moveRed)
                        .symbolEffect(.pulse, isActive: m.running)
                }
                Text("\(Int(m.calories)) kcal").font(.title3.weight(.semibold)).foregroundStyle(Color.moveRed)
                Text(String(format: "%.2f km", m.distance / 1000)).font(.title3.weight(.semibold))
                    .foregroundStyle(Color.standCyan)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                circleButton("stop.fill", .red) { m.end() }
                circleButton(m.running ? "pause.fill" : "play.fill", .yellow) { m.togglePause() }
            }
        }
        .tabViewStyle(.verticalPage)
        .navigationBarBackButtonHidden()
    }
    func circleButton(_ icon: String, _ c: Color, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: icon).font(.title2).foregroundStyle(c)
                .frame(width: 60, height: 60).background(c.opacity(0.25), in: Circle())
        }.buttonStyle(.plain)
    }
}

struct SummaryView: View {
    @EnvironmentObject var m: WorkoutManager
    var body: some View {
        ScrollView {
            if let r = m.summary {
                VStack(alignment: .leading, spacing: 8) {
                    Text(r.type).font(.headline).foregroundStyle(Color.exerciseGreen)
                    row("timer", fmt(r.duration), .yellow)
                    row("flame.fill", "\(Int(r.calories)) kcal", .moveRed)
                    row("heart.fill", "\(Int(r.avgHeartRate)) bpm avg", .red)
                    row("location.fill", String(format: "%.2f km", r.distance/1000), .standCyan)
                    Button("Done") { m.reset() }.tint(.exerciseGreen)
                }
            }
        }.navigationBarBackButtonHidden()
    }
    func row(_ i: String, _ t: String, _ c: Color) -> some View {
        Label { Text(t).font(.title3.weight(.semibold)) } icon: { Image(systemName: i).foregroundStyle(c) }
    }
}
