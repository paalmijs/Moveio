import SwiftUI
import Combine
import CoreLocation
import HealthKit
import UIKit

// MARK: - Sports
struct PhoneSport: Identifiable, Hashable {
    let id: String            // also the name saved in history
    let icon: String
    let hk: HKWorkoutActivityType
    let met: Double           // used to estimate calories
    let gps: Bool             // track distance with GPS
    var name: String { id }
}

let phoneSports: [PhoneSport] = [
    PhoneSport(id: "Running", icon: "figure.run", hk: .running, met: 9.8, gps: true),
    PhoneSport(id: "Walking", icon: "figure.walk", hk: .walking, met: 3.8, gps: true),
    PhoneSport(id: "Cycling", icon: "figure.outdoor.cycle", hk: .cycling, met: 7.5, gps: true),
    PhoneSport(id: "Strength", icon: "dumbbell.fill", hk: .traditionalStrengthTraining, met: 5.0, gps: false),
    PhoneSport(id: "HIIT", icon: "flame.fill", hk: .highIntensityIntervalTraining, met: 8.0, gps: false),
    PhoneSport(id: "Yoga", icon: "figure.yoga", hk: .yoga, met: 2.5, gps: false),
    PhoneSport(id: "Swimming", icon: "figure.pool.swim", hk: .swimming, met: 6.0, gps: false),
    PhoneSport(id: "Other", icon: "sparkles", hk: .other, met: 4.0, gps: false),
]

func hmsString(_ t: TimeInterval) -> String {
    let s = Int(t); return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
}

// MARK: - Workout engine (timer + GPS)
final class PhoneWorkout: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State { case idle, running, paused, finished }

    @Published var state: State = .idle
    @Published var sport: PhoneSport?
    @Published var elapsed: TimeInterval = 0
    @Published var distance: Double = 0          // meters
    @Published var calories: Double = 0
    @Published var locationDenied = false
    @Published var watchMessage = ""
    @Published var summary: WorkoutRecord?

    private let lm = CLLocationManager()
    private let health = HKHealthStore()
    private var timer: Timer?
    private var startDate = Date()
    private var accumulated: TimeInterval = 0
    private var resumeDate: Date?
    private var last: CLLocation?

    override init() {
        super.init()
        lm.delegate = self
        lm.activityType = .fitness
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.distanceFilter = 5
    }

    var weightKg: Double {
        let w = UserDefaults.standard.double(forKey: "p_weight")
        return w > 30 ? w : 70
    }

    var paceText: String {
        guard distance > 50, elapsed > 0 else { return "--" }
        if sport?.id == "Cycling" {
            return String(format: "%.1f", (distance / 1000) / (elapsed / 3600))
        }
        let secPerKm = elapsed / (distance / 1000)
        return String(format: "%d:%02d", Int(secPerKm) / 60, Int(secPerKm) % 60)
    }
    var paceUnit: String { sport?.id == "Cycling" ? "km/h" : "min/km" }

    // MARK: Health permission
    func requestHealth() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned),
                                        HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)]
        health.requestAuthorization(toShare: share, read: []) { _, _ in }
    }

    // MARK: Start on iPhone
    func start(_ s: PhoneSport) {
        sport = s; state = .running
        elapsed = 0; distance = 0; calories = 0; summary = nil; locationDenied = false
        startDate = Date(); accumulated = 0; resumeDate = Date(); last = nil
        UIApplication.shared.isIdleTimerDisabled = true
        if s.gps { startLocation() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        haptic()
    }

    private func startLocation() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        if modes.contains("location") {                      // only if the capability was added
            lm.allowsBackgroundLocationUpdates = true
            lm.showsBackgroundLocationIndicator = true
        }
        switch lm.authorizationStatus {
        case .notDetermined: lm.requestWhenInUseAuthorization()
        case .denied, .restricted: locationDenied = true
        default: lm.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        guard sport?.gps == true, state == .running || state == .paused else { return }
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: locationDenied = false; m.startUpdatingLocation()
        case .denied, .restricted: locationDenied = true
        default: break
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard state == .running else { last = nil; return }
        for l in locs {
            guard l.horizontalAccuracy >= 0, l.horizontalAccuracy < 30 else { continue }
            if let p = last {
                let d = l.distance(from: p)
                let dt = l.timestamp.timeIntervalSince(p.timestamp)
                if dt > 0, d / dt < 12 { distance += d }     // ignore GPS jumps (> 43 km/h)
            }
            last = l
        }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}

    private func tick() {
        guard state == .running else { return }
        elapsed = accumulated + Date().timeIntervalSince(resumeDate ?? Date())
        calories = (sport?.met ?? 5) * weightKg * elapsed / 3600
    }

    func pause() {
        guard state == .running else { return }
        accumulated += Date().timeIntervalSince(resumeDate ?? Date())
        resumeDate = nil; elapsed = accumulated; state = .paused; last = nil
    }

    func resume() {
        guard state == .paused else { return }
        resumeDate = Date(); state = .running
    }

    func discard() {
        timer?.invalidate(); lm.stopUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = false
        state = .idle
    }

    func finish() {
        guard state == .running || state == .paused else { return }
        if state == .running { accumulated += Date().timeIntervalSince(resumeDate ?? Date()) }
        elapsed = accumulated
        calories = (sport?.met ?? 5) * weightKg * elapsed / 3600
        timer?.invalidate(); lm.stopUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = false

        let end = Date()
        let rec = WorkoutRecord(type: sport?.id ?? "Other", date: end, duration: elapsed,
                                calories: calories, avgHeartRate: 0, distance: distance)
        ConnectivityManager.shared.add(rec)
        saveToHealth(start: startDate, end: end)
        summary = rec
        state = .finished
        haptic()
    }

    private func saveToHealth(start: Date, end: Date) {
        guard HKHealthStore.isHealthDataAvailable(), let s = sport else { return }
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = s.hk
        cfg.locationType = s.gps ? .outdoor : .indoor
        let builder = HKWorkoutBuilder(healthStore: health, configuration: cfg, device: .local())
        let cal = calories, dist = distance
        builder.beginCollection(withStart: start) { ok, _ in
            guard ok else { return }
            var samples: [HKSample] = []
            if cal > 0 {
                samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: cal),
                                                start: start, end: end))
            }
            if s.gps, dist > 0 {
                let type = HKQuantityType(s.id == "Cycling" ? .distanceCycling : .distanceWalkingRunning)
                samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: .meter(), doubleValue: dist),
                                                start: start, end: end))
            }
            builder.add(samples) { _, _ in
                builder.endCollection(withEnd: end) { _, _ in builder.finishWorkout { _, _ in } }
            }
        }
    }

    // MARK: Start on Apple Watch
    func startOnWatch(_ s: PhoneSport) {
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = s.hk
        cfg.locationType = s.gps ? .outdoor : .indoor
        watchMessage = "Contacting your Apple Watch..."
        health.startWatchApp(with: cfg) { ok, err in
            DispatchQueue.main.async {
                self.watchMessage = ok
                    ? "Started on your Apple Watch. The result will appear here when you finish."
                    : "Couldn't reach your Watch (\(err?.localizedDescription ?? "unknown error")). Open Moveio on the Watch and try again."
            }
        }
    }
}

// MARK: - Entry card (shown at the top of Summary)
struct StartWorkoutCard: View {
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "figure.run.circle.fill").font(.system(size: 36))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start workout").font(.headline)
                    Text("Track on iPhone or start on Apple Watch").font(.caption).opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(16).frame(maxWidth: .infinity)
            .background(Theme.move.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $show) { WorkoutFlowView() }
    }
}

// MARK: - Workout screen
struct WorkoutFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var w = PhoneWorkout()
    @State private var selected = phoneSports[0]
    @State private var confirmEnd = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch w.state {
            case .idle: picker
            case .running, .paused: live
            case .finished: done
            }
        }
        .confetti(trigger: w.state == .finished)
        .onAppear { w.requestHealth() }
    }

    // Choose a sport and where to start
    var picker: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Workout").font(.largeTitle.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(phoneSports) { s in
                        Button { withAnimation(.spring(duration: 0.3)) { selected = s } } label: {
                            VStack(spacing: 8) {
                                Image(systemName: s.icon).font(.title)
                                Text(s.name).font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                            .background(selected == s ? Theme.move : Theme.card,
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .foregroundStyle(selected == s ? Color.white : Color.primary)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if selected.gps {
                Label("Distance is tracked with GPS. Allow location access when asked.", systemImage: "location.fill")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Button { w.start(selected) } label: {
                Text("Start on iPhone").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(Theme.move).controlSize(.large)

            Button { w.startOnWatch(selected) } label: {
                Label("Start on Apple Watch", systemImage: "applewatch").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered).controlSize(.large)

            if !w.watchMessage.isEmpty {
                Text(w.watchMessage).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    // Live tracking
    var live: some View {
        VStack(spacing: 24) {
            Text(w.sport?.name ?? "").font(.headline).foregroundStyle(.secondary).padding(.top, 24)
            Text(hmsString(w.elapsed))
                .font(.system(size: 68, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
                .foregroundStyle(w.state == .paused ? Color.secondary : Color.primary)
            HStack {
                if w.sport?.gps == true {
                    stat(String(format: "%.2f", w.distance / 1000), "km", Theme.stand)
                    stat(w.paceText, w.paceUnit, Theme.exercise)
                }
                stat("\(Int(w.calories))", "kcal", Theme.move)
            }
            if w.locationDenied {
                Label("Location access is off, so distance can't be tracked. Turn it on in Settings > Privacy > Location Services.",
                      systemImage: "location.slash.fill")
                    .font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal)
            }
            Spacer()
            HStack(spacing: 28) {
                roundButton("stop.fill", .red) { confirmEnd = true }
                roundButton(w.state == .paused ? "play.fill" : "pause.fill", Theme.exercise) {
                    w.state == .paused ? w.resume() : w.pause()
                }
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal)
        .confirmationDialog("End workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and save") { w.finish() }
            Button("Discard", role: .destructive) { w.discard() }
            Button("Keep going", role: .cancel) {}
        }
    }

    // Summary
    var done: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 80)).foregroundStyle(Theme.exercise)
            Text("Workout saved").font(.title.bold())
            if let r = w.summary {
                Text(r.type).font(.headline).foregroundStyle(.secondary)
                HStack {
                    stat(hmsString(r.duration), "time", Theme.exercise)
                    if r.distance > 0 { stat(String(format: "%.2f", r.distance / 1000), "km", Theme.stand) }
                    stat("\(Int(r.calories))", "kcal", Theme.move)
                }
                Text("Calories are estimated from your weight and the activity.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(Theme.move).controlSize(.large)
        }
        .padding()
    }

    func stat(_ v: String, _ unit: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(unit).font(.caption).foregroundStyle(c)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func roundButton(_ icon: String, _ c: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title).foregroundStyle(c == .red ? Color.white : Color.black)
                .frame(width: 76, height: 76).background(c, in: Circle())
        }.buttonStyle(.plain)
    }
}
