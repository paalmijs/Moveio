// WATCH target only (Moveio Watch App Watch App)
import SwiftUI
import Combine
import WatchKit
import UserNotifications

// MARK: - Helpers
func mmss(_ t: TimeInterval) -> String {
    let s = Int(t.rounded(.up)); return String(format: "%02d:%02d", s / 60, s % 60)
}

func logSession(_ type: String, duration: TimeInterval) {
    ConnectivityManager.shared.add(WorkoutRecord(type: type, date: .now, duration: duration,
                                                 calories: 0, avgHeartRate: 0, distance: 0))
}

// MARK: - Countdown timer (computed from an end date)
final class Countdown: ObservableObject {
    @Published var remaining: TimeInterval = 0
    @Published var total: TimeInterval = 0
    @Published var running = false
    var onFinish: (() -> Void)?
    private var end: Date?
    private var timer: Timer?

    func start(_ seconds: TimeInterval, title: String? = nil) {
        total = seconds; remaining = seconds
        end = Date().addingTimeInterval(seconds)
        running = true
        if let title { schedule(seconds, title) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
    }

    private func tick() {
        guard let end else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 {
            stop(cancel: false)
            WKInterfaceDevice.current().play(.success)
            onFinish?()
        }
    }

    func stop(cancel: Bool = true) {
        timer?.invalidate(); timer = nil
        running = false; end = nil
        if cancel { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
    }

    private func schedule(_ seconds: TimeInterval, _ title: String) {
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
            c.add(UNNotificationRequest(identifier: "countdown", content: content, trigger: trigger))
        }
    }
}

// MARK: - Home menu
struct HomeView: View {
    var body: some View {
        List {
            hub("Workout", "figure.run", .moveRed) { StartView() }
            hub("Meditation", "leaf.fill", Color.standCyan) { MeditationView() }
            hub("Pomodoro", "timer", Color.moveRed) { PomodoroView() }
            hub("Stretching", "figure.flexibility", Color.exerciseGreen) { StretchView() }
        }
        .navigationTitle("Moveio")
    }

    private func hub<D: View>(_ t: String, _ icon: String, _ c: Color,
                              @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(.black)
                    .frame(width: 34, height: 34).background(c, in: Circle())
                Text(t).font(.headline)
            }.padding(.vertical, 4)
        }
        .listItemTint(c.opacity(0.22))
    }
}

// MARK: - Meditation
struct MeditationView: View {
    var body: some View {
        List([1, 3, 5, 10], id: \.self) { m in
            NavigationLink { MeditationSession(minutes: m) } label: {
                Label("\(m) min", systemImage: "leaf.fill").foregroundStyle(Color.standCyan).font(.headline)
            }
        }
        .navigationTitle("Meditation")
    }
}

struct MeditationSession: View {
    let minutes: Int
    @StateObject private var cd = Countdown()
    @State private var inhale = false
    @State private var done = false
    @Environment(\.dismiss) private var dismiss
    private let breath = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            if done {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Color.standCyan)
                Text("Well done!").font(.headline)
                Button("Done") { dismiss() }.tint(Color.standCyan)
            } else {
                ZStack {
                    Circle().fill(Color.standCyan.opacity(0.35)).scaleEffect(inhale ? 1 : 0.5)
                    Circle().stroke(Color.standCyan, lineWidth: 2).scaleEffect(inhale ? 1 : 0.5)
                    Text(inhale ? "Inhale" : "Exhale").font(.footnote.weight(.medium))
                }
                .frame(height: 100)
                .animation(.easeInOut(duration: 4), value: inhale)
                Text(mmss(cd.remaining)).font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(Color.standCyan)
            }
        }
        .navigationBarBackButtonHidden(done)
        .onAppear {
            cd.onFinish = {
                logSession("Meditation", duration: Double(minutes) * 60)
                done = true
            }
            cd.start(Double(minutes) * 60, title: "Meditation complete 🍃")
            inhale = true
        }
        .onReceive(breath) { _ in inhale.toggle() }
        .onDisappear { cd.stop() }
    }
}

// MARK: - Pomodoro
struct PomodoroView: View {
    enum Phase { case focus, short, long }
    @StateObject private var cd = Countdown()
    @State private var phase: Phase = .focus
    @State private var doneCount = 0

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
    var color: Color { phase == .focus ? .moveRed : .exerciseGreen }
    var progress: Double { cd.running && cd.total > 0 ? 1 - cd.remaining / cd.total : 0 }

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(color)
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 8)
                Circle().trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(mmss(cd.running ? cd.remaining : length))
                    .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(height: 100)
            HStack {
                Button(cd.running ? "Stop" : "Start") {
                    if cd.running { cd.stop() }
                    else { cd.start(length, title: phase == .focus ? "Time for a break ☕️" : "Back to work 🍅") }
                }.tint(color)
                Text("🍅 \(doneCount)").font(.footnote)
            }
        }
        .navigationTitle("Pomodoro")
        .onAppear {
            cd.onFinish = {
                if phase == .focus {
                    doneCount += 1
                    logSession("Pomodoro", duration: 25 * 60)
                    phase = doneCount % 4 == 0 ? .long : .short
                } else {
                    phase = .focus
                }
            }
        }
        .onDisappear { cd.stop() }
    }
}

// MARK: - Stretching
struct StretchStep: Identifiable {
    let id = UUID()
    let name: String, hint: String, icon: String, seconds: TimeInterval
}

let stretchRoutine = [
    StretchStep(name: "Neck", hint: "Slowly tilt your head to the side", icon: "figure.mind.and.body", seconds: 30),
    StretchStep(name: "Shoulders", hint: "Roll your shoulders slowly backward", icon: "figure.arms.open", seconds: 30),
    StretchStep(name: "Arms", hint: "Reach both arms overhead", icon: "figure.stand", seconds: 30),
    StretchStep(name: "Back", hint: "Fold forward and relax", icon: "figure.cooldown", seconds: 30),
    StretchStep(name: "Hips", hint: "Deep lunge, hold the pose", icon: "figure.flexibility", seconds: 30),
    StretchStep(name: "Calves", hint: "Lean on a wall, one leg back", icon: "figure.yoga", seconds: 30),
]

struct StretchView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.flexibility").font(.system(size: 36)).foregroundStyle(Color.exerciseGreen)
            Text("\(stretchRoutine.count) exercises · \(Int(stretchRoutine.map(\.seconds).reduce(0, +) / 60)) min")
                .font(.footnote)
            NavigationLink { StretchSession() } label: { Text("Start") }.tint(Color.exerciseGreen)
        }
        .navigationTitle("Stretching")
    }
}

struct StretchSession: View {
    @StateObject private var cd = Countdown()
    @State private var idx = 0
    @State private var done = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 4) {
            if done {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Color.exerciseGreen)
                Text("All done!").font(.headline)
                Button("Close") { dismiss() }.tint(Color.exerciseGreen)
            } else {
                let s = stretchRoutine[idx]
                Text("\(idx + 1)/\(stretchRoutine.count)").font(.caption2).foregroundStyle(.secondary)
                Image(systemName: s.icon).font(.system(size: 30)).foregroundStyle(Color.exerciseGreen)
                Text(s.name).font(.headline)
                Text(s.hint).font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text(mmss(cd.remaining)).font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundStyle(Color.exerciseGreen)
            }
        }
        .onAppear {
            cd.onFinish = {
                if idx + 1 < stretchRoutine.count {
                    idx += 1
                    cd.start(stretchRoutine[idx].seconds)
                } else {
                    logSession("Stretching", duration: stretchRoutine.map(\.seconds).reduce(0, +))
                    done = true
                }
            }
            cd.start(stretchRoutine[0].seconds)
        }
        .onDisappear { cd.stop() }
    }
}
