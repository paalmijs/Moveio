// Tikai iPHONE target
import SwiftUI
import Combine
import Charts
import HealthKit

// MARK: - Profila dati
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()
    private let d = UserDefaults.standard

    @Published var onboarded: Bool { didSet { d.set(onboarded, forKey: "p_onboarded") } }
    @Published var name: String { didSet { d.set(name, forKey: "p_name") } }
    @Published var birthday: Date? { didSet { d.set(birthday, forKey: "p_birthday") } }
    @Published var sex: String { didSet { d.set(sex, forKey: "p_sex") } }   // female, male, other, ""
    @Published var height: Double { didSet { d.set(height, forKey: "p_height") } }
    @Published var weight: Double { didSet { d.set(weight, forKey: "p_weight") } }
    @Published var cycleEnabled: Bool { didSet { d.set(cycleEnabled, forKey: "p_cycle") } }
    @Published var importing = false
    @Published var importNote = ""

    init() {
        onboarded = d.bool(forKey: "p_onboarded")
        name = d.string(forKey: "p_name") ?? ""
        birthday = d.object(forKey: "p_birthday") as? Date
        sex = d.string(forKey: "p_sex") ?? ""
        height = d.double(forKey: "p_height")
        weight = d.double(forKey: "p_weight")
        cycleEnabled = d.bool(forKey: "p_cycle")
    }

    var age: Int? {
        birthday.flatMap { Calendar.current.dateComponents([.year], from: $0, to: .now).year }
    }
    var bmi: Double? {
        height > 0 && weight > 0 ? weight / pow(height / 100, 2) : nil
    }

    // Imports from Apple Health: date of birth, sex, height, weight
    func importFromHealth() {
        guard HKHealthStore.isHealthDataAvailable() else {
            importNote = "Apple Health is not available on this device."; return
        }
        let hs = HKHealthStore()
        let read: Set<HKObjectType> = [
            HKCharacteristicType(.dateOfBirth), HKCharacteristicType(.biologicalSex),
            HKQuantityType(.height), HKQuantityType(.bodyMass)
        ]
        importing = true
        hs.requestAuthorization(toShare: [], read: read) { [weak self] _, _ in
            guard let self else { return }
            let dob: Date? = (try? hs.dateOfBirthComponents()).flatMap { Calendar.current.date(from: $0) }
            let sx: String? = {
                guard let b = try? hs.biologicalSex().biologicalSex else { return nil }
                switch b {
                case .female: return "female"
                case .male: return "male"
                case .other: return "other"
                default: return nil
                }
            }()
            self.latest(.height, .meterUnit(with: .centi), hs) { h in
                self.latest(.bodyMass, .gramUnit(with: .kilo), hs) { w in
                    DispatchQueue.main.async {
                        var found = 0
                        if let dob { self.birthday = dob; found += 1 }
                        if let sx { self.sex = sx; found += 1; if sx == "female" { self.cycleEnabled = true } }
                        if let h { self.height = (h * 10).rounded() / 10; found += 1 }
                        if let w { self.weight = (w * 10).rounded() / 10; found += 1 }
                        self.importing = false
                        self.importNote = found > 0
                            ? "Imported \(found) fields from Apple Health. Check them on the next step."
                            : "No Health data found, or permission was not granted. Please fill it in manually."
                    }
                }
            }
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ hs: HKHealthStore,
                        _ done: @escaping (Double?) -> Void) {
        let q = HKSampleQuery(sampleType: HKQuantityType(id), predicate: nil, limit: 1,
                              sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, s, _ in
            done((s?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
        }
        hs.execute(q)
    }
}

// MARK: - Profile fields (shared by onboarding and editing)
struct ProfileFields: View {
    @EnvironmentObject var p: ProfileStore

    var birthdayBinding: Binding<Date> {
        Binding(get: { p.birthday ?? Calendar.current.date(byAdding: .year, value: -25, to: .now)! },
                set: { p.birthday = $0 })
    }

    var body: some View {
        Section("About you") {
            TextField("Name", text: $p.name)
            DatePicker("Date of birth", selection: birthdayBinding, in: ...Date(), displayedComponents: .date)
            Picker("Sex", selection: $p.sex) {
                Text("Not specified").tag("")
                Text("Female").tag("female")
                Text("Male").tag("male")
                Text("Other").tag("other")
            }
            HStack {
                Text("Height"); Spacer()
                TextField("0", value: $p.height, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                Text("cm").foregroundStyle(.secondary)
            }
            HStack {
                Text("Weight"); Spacer()
                TextField("0", value: $p.weight, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                Text("kg").foregroundStyle(.secondary)
            }
        }
        if p.sex == "female" {
            Section("Menstrual cycle") {
                Toggle("Show cycle section", isOn: $p.cycleEnabled)
                Text("Cycle data stays on your iPhone. You can read it from Apple Health or log it by hand.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Onboarding (profile setup)
struct OnboardingView: View {
    @EnvironmentObject var p: ProfileStore
    @AppStorage("weeklyGoal") private var goal = 150
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: details
                default: finish
                }
            }
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(step == i ? Theme.move : Color(.tertiarySystemFill)).frame(width: 8, height: 8)
                }
            }.padding(.bottom, 8)
            HStack {
                if step > 0 { Button("Back") { step -= 1 }.buttonStyle(.bordered) }
                Button(step < 2 ? "Continue" : "Get started") {
                    if step < 2 { step += 1 } else { p.onboarded = true }
                }
                .buttonStyle(.borderedProminent).tint(Theme.move).controlSize(.large)
            }.padding(.bottom)
        }
        .animation(.easeInOut, value: step)
    }

    var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "figure.run.circle.fill").font(.system(size: 90)).foregroundStyle(Theme.move)
            Text("Welcome to Moveio").font(.largeTitle.bold())
            Text("Let's set up your profile. Import your details from Apple Health or enter them yourself.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 30)
            TextField("Your name", text: $p.name)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 40)
            Button { p.importFromHealth() } label: {
                Label(p.importing ? "Importing..." : "Import from Apple Health", systemImage: "heart.fill")
            }
            .buttonStyle(.bordered).tint(.red).disabled(p.importing)
            if !p.importNote.isEmpty {
                Text(p.importNote).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
            }
            Spacer()
        }
    }

    var details: some View {
        Form { ProfileFields() }
    }

    var finish: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 50)).foregroundStyle(Theme.exercise)
                    Text(p.name.isEmpty ? "Almost ready!" : "Almost ready, \(p.name)!").font(.title3.bold())
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            Section("Weekly goal") {
                Stepper("\(goal) min per week", value: $goal, in: 30...900, step: 15)
            }
            Section {
                Text("You can change everything later in Profile.").foregroundStyle(.secondary)
            }
        }
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form { ProfileFields() }
                .navigationTitle("Profile")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Profils
struct ProfileView: View {
    @EnvironmentObject var conn: ConnectivityManager
    @EnvironmentObject var p: ProfileStore
    @AppStorage("weeklyGoal") private var goal = 150
    @State private var confirm = false
    @State private var editing = false

    var sexText: String {
        switch p.sex {
        case "female": return "Female"
        case "male": return "Male"
        case "other": return "Other"
        default: return ""
        }
    }
    var details: String {
        let parts: [String?] = [p.age.map { "\($0) g." }, sexText.isEmpty ? nil : sexText]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Theme.move.gradient)
                            Text(String(p.name.first ?? "M").uppercased()).font(.title.bold()).foregroundStyle(Color.white)
                        }.frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name.isEmpty ? "Moveio user" : p.name).font(.title3.bold())
                            if !details.isEmpty { Text(details).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                    if p.height > 0 || p.weight > 0 {
                        HStack {
                            stat("Height", p.height > 0 ? "\(Int(p.height)) cm" : "–")
                            stat("Weight", p.weight > 0 ? String(format: "%.1f kg", p.weight) : "–")
                            stat("BMI", p.bmi.map { String(format: "%.1f", $0) } ?? "–")
                        }
                    }
                    Button("Edit profile") { editing = true }
                    Button { p.importFromHealth() } label: {
                        Label(p.importing ? "Importing..." : "Refresh from Apple Health", systemImage: "heart.fill")
                    }.disabled(p.importing)
                    if !p.importNote.isEmpty { Text(p.importNote).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Weekly goal") {
                    Stepper("\(goal) min per week", value: $goal, in: 30...900, step: 15)
                }
                Section("Tracking") {
                    NavigationLink { BodyView() } label: { Label("Body measurements", systemImage: "scalemass.fill") }
                    NavigationLink { RemindersView() } label: { Label("Reminders", systemImage: "bell.fill") }
                    if p.sex == "female" && p.cycleEnabled {
                        NavigationLink { CycleView() } label: {
                            Label("Menstrual cycle", systemImage: "drop.circle.fill").foregroundStyle(Theme.move)
                        }
                    }
                }
                Section("Data") {
                    Text("\(conn.records.count) saved sessions")
                    Label(conn.watchStatus, systemImage: "applewatch").foregroundStyle(.secondary)
                    Button("Delete all sessions", role: .destructive) { confirm = true }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $editing) { EditProfileView() }
            .confirmationDialog("Delete all sessions?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { RouteStore.deleteAll(); conn.remove(ids: conn.records.map(\.id)) }
            }
        }
    }

    func stat(_ t: String, _ v: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.headline)
            Text(t).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

// MARK: - Menstrual cycle
final class CycleStore: ObservableObject {
    @Published var healthStarts: [Date] = []
    @Published var healthDays: Set<String> = []
    @Published var manualStarts: [Date] = []
    private let hs = HKHealthStore()
    private let key = "cycleManual"
    private let cal = Calendar.current

    init() {
        let t = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        manualStarts = t.map { Date(timeIntervalSince1970: $0) }.sorted()
        if UserDefaults.standard.bool(forKey: "cycleHealthAsked") { request() }
    }

    func request() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        UserDefaults.standard.set(true, forKey: "cycleHealthAsked")
        hs.requestAuthorization(toShare: [], read: [HKCategoryType(.menstrualFlow)]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func refresh() {
        let from = cal.date(byAdding: .year, value: -2, to: .now)!
        let q = HKSampleQuery(sampleType: HKCategoryType(.menstrualFlow),
                              predicate: HKQuery.predicateForSamples(withStart: from, end: .now),
                              limit: HKObjectQueryNoLimit,
                              sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { [weak self] _, s, _ in
            let c = Calendar.current
            let none = HKCategoryValueMenstrualFlow.none.rawValue
            let days = Set((s as? [HKCategorySample] ?? []).filter { $0.value != none }
                .map { c.startOfDay(for: $0.startDate) }).sorted()
            var starts: [Date] = []
            var prev: Date?
            for d in days {
                let gap = prev.map { c.dateComponents([.day], from: $0, to: d).day ?? 99 } ?? 99
                if gap > 2 { starts.append(d) }
                prev = d
            }
            let keys = Set(days.map { dayKey($0) })
            DispatchQueue.main.async { self?.healthStarts = starts; self?.healthDays = keys }
        }
        hs.execute(q)
    }

    func addManual(_ d: Date) {
        manualStarts.append(cal.startOfDay(for: d)); manualStarts.sort(); save()
    }
    func removeManual(_ d: Date) {
        manualStarts.removeAll { $0 == d }; save()
    }
    private func save() {
        UserDefaults.standard.set(manualStarts.map(\.timeIntervalSince1970), forKey: key)
    }

    // All cycle starts (Health + manual), deduplicated
    var starts: [Date] {
        let all = (healthStarts + manualStarts).map { cal.startOfDay(for: $0) }.sorted()
        var out: [Date] = []
        for d in all {
            if let l = out.last, (cal.dateComponents([.day], from: l, to: d).day ?? 99) <= 3 { continue }
            out.append(d)
        }
        return out
    }
    var lengths: [Int] {
        zip(starts, starts.dropFirst()).compactMap { a, b in
            let n = cal.dateComponents([.day], from: a, to: b).day ?? 0
            return (15...60).contains(n) ? n : nil
        }
    }
    var avgLength: Int {
        let l = Array(lengths.suffix(6))
        return l.isEmpty ? 28 : Int((Double(l.reduce(0, +)) / Double(l.count)).rounded())
    }
    var lastStart: Date? { starts.last }
    var dayOfCycle: Int? {
        lastStart.map { (cal.dateComponents([.day], from: $0, to: cal.startOfDay(for: .now)).day ?? 0) + 1 }
    }
    var nextStart: Date? { lastStart.flatMap { cal.date(byAdding: .day, value: avgLength, to: $0) } }
    var daysUntilNext: Int? {
        nextStart.map { cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: $0).day ?? 0 }
    }

    func phase(_ day: Int) -> (String, Color) {
        let ov = avgLength - 14
        if day > avgLength { return ("Longer than usual", Color.gray) }
        if day <= 5 { return ("Period", Theme.move) }
        if day < ov - 1 { return ("Follicular phase", Color.orange) }
        if day <= ov + 1 { return ("Ovulation window (approx.)", Color.pink) }
        return ("Luteal phase", Color.purple)
    }

    var periodDays: Set<String> {
        var s = healthDays
        for m in manualStarts {
            for i in 0..<5 { s.insert(dayKey(cal.date(byAdding: .day, value: i, to: m)!)) }
        }
        return s
    }
    var predictedDays: Set<String> {
        guard let n = nextStart else { return [] }
        var s = Set<String>()
        for k in 0..<2 {
            let st = cal.date(byAdding: .day, value: k * avgLength, to: n)!
            for i in 0..<5 { s.insert(dayKey(cal.date(byAdding: .day, value: i, to: st)!)) }
        }
        return s
    }
}

struct CycleLen: Identifiable {
    let id: Int
    let days: Int
}

struct CycleView: View {
    @StateObject private var c = CycleStore()
    @State private var logDate = Date()
    @State private var month = Date()
    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summary
                calendarCard
                if c.lengths.count >= 2 { chartCard }
                logCard
                Text("This information is approximate only. It is not medical advice and must not be used for contraception. If your cycle is irregular or painful, talk to a doctor.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }.padding()
        }
        .navigationTitle("Cycle")
        .onAppear { c.refresh() }
    }

    var summary: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                if let day = c.dayOfCycle, let next = c.nextStart, let until = c.daysUntilNext {
                    let ph = c.phase(day)
                    HStack(spacing: 20) {
                        ZStack {
                            Circle().stroke(ph.1.opacity(0.2), lineWidth: 14)
                            Circle().trim(from: 0, to: min(Double(day) / Double(c.avgLength), 1))
                                .stroke(ph.1.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(day)").font(.system(size: 34, weight: .bold, design: .rounded))
                                Text("day").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(width: 110, height: 110)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ph.0).font(.headline).foregroundStyle(ph.1)
                            if until >= 0 {
                                Text("Next period around \(next.formatted(.dateTime.day().month(.wide))) (in \(until) d)")
                            } else {
                                Text("Period expected \(-until) d ago")
                            }
                            Text("Average cycle: \(c.avgLength) d").font(.caption).foregroundStyle(.secondary)
                        }.font(.subheadline)
                    }
                } else {
                    Label("No data yet", systemImage: "drop.circle.fill").font(.headline).foregroundStyle(Theme.move)
                    Text("Connect Apple Health or log your last period start below to see a prediction.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button { c.request() } label: { Label("Read from Apple Health", systemImage: "heart.fill") }
                    .buttonStyle(.bordered).tint(.red)
            }
        }
    }

    var calendarCard: some View {
        let monthStart = cal.dateInterval(of: .month, for: month)!.start
        let count = cal.range(of: .day, in: .month, for: month)!.count
        let offset = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let period = c.periodDays
        let predicted = c.predictedDays
        return card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(monthStart.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right") }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 34) }
                    ForEach(1...count, id: \.self) { day in
                        let date = cal.date(byAdding: .day, value: day - 1, to: monthStart)!
                        let key = dayKey(date)
                        let isPeriod = period.contains(key)
                        let isPred = predicted.contains(key) && !isPeriod
                        Text("\(day)").font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(isPeriod ? Theme.move.opacity(0.9) : Color(.tertiarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(cal.isDateInToday(date) ? Color.primary : (isPred ? Theme.move.opacity(0.7) : Color.clear),
                                        style: StrokeStyle(lineWidth: 1.5, dash: isPred && !cal.isDateInToday(date) ? [3] : [])))
                            .foregroundStyle(isPeriod ? Color.white : Color.secondary)
                    }
                }
                HStack(spacing: 14) {
                    Label("Period", systemImage: "square.fill").foregroundStyle(Theme.move)
                    Label("Prediction", systemImage: "square.dashed").foregroundStyle(Theme.move.opacity(0.7))
                }.font(.caption)
            }
        }
    }

    var chartCard: some View {
        let items = Array(c.lengths.suffix(6).enumerated()).map { CycleLen(id: $0.offset + 1, days: $0.element) }
        return card {
            VStack(alignment: .leading) {
                Text("Recent cycle lengths").font(.headline)
                Chart(items) { i in
                    BarMark(x: .value("Cycle", "\(i.id)"), y: .value("Days", i.days))
                        .foregroundStyle(Theme.move.gradient).cornerRadius(5)
                }
                .chartYScale(domain: 0...45)
                .frame(height: 130)
            }
        }
    }

    var logCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Log period start").font(.headline)
                DatePicker("Date", selection: $logDate, in: ...Date(), displayedComponents: .date)
                Button("Save") { c.addManual(logDate) }
                    .buttonStyle(.borderedProminent).tint(Theme.move)
                if !c.manualStarts.isEmpty {
                    Divider()
                    ForEach(c.manualStarts.reversed(), id: \.self) { d in
                        HStack {
                            Text(d.formatted(date: .long, time: .omitted))
                            Spacer()
                            Button(role: .destructive) { c.removeManual(d) } label: { Image(systemName: "trash") }
                        }.font(.subheadline)
                    }
                }
            }
        }
    }
}
