// Tikai iPHONE target
import SwiftUI
import Combine
import UIKit

// MARK: - Animation helpers
struct FadeIn: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 18)
            .onAppear {
                withAnimation(.spring(duration: 0.6, bounce: 0.25).delay(Double.random(in: 0...0.2))) { on = true }
            }
    }
}
extension View {
    func fadeIn() -> some View { modifier(FadeIn()) }
    func confetti(trigger: Bool) -> some View { modifier(ConfettiModifier(trigger: trigger)) }
}

struct AnimatedRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 14
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle().trim(from: 0, to: shown)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { withAnimation(.spring(duration: 1.0, bounce: 0.2)) { shown = min(max(progress, 0), 1) } }
        .onChange(of: progress) { _, new in
            withAnimation(.spring(duration: 0.8)) { shown = min(max(new, 0), 1) }
        }
    }
}

struct ConfettiView: View {
    struct Piece: Identifiable {
        let id = UUID()
        let x = CGFloat.random(in: -180...180)
        let delay = Double.random(in: 0...0.4)
        let duration = Double.random(in: 1.4...2.4)
        let size = CGFloat.random(in: 6...11)
        let spin = Double.random(in: 180...720)
        let color = [Theme.move, Theme.exercise, Theme.stand, Color.orange, Color.yellow].randomElement()!
    }
    @State private var go = false
    private let pieces = (0..<50).map { _ in Piece() }

    var body: some View {
        ZStack {
            ForEach(pieces) { p in
                RoundedRectangle(cornerRadius: 2).fill(p.color)
                    .frame(width: p.size, height: p.size * 1.6)
                    .rotationEffect(.degrees(go ? p.spin : 0))
                    .offset(x: p.x * (go ? 1.3 : 0.2), y: go ? 560 : -40)
                    .opacity(go ? 0 : 1)
                    .animation(.easeIn(duration: p.duration).delay(p.delay), value: go)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .onAppear { go = true }
    }
}

struct ConfettiModifier: ViewModifier {
    let trigger: Bool
    @State private var show = false
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) { if show { ConfettiView() } }
            .onChange(of: trigger) { _, new in
                guard new else { return }
                haptic()
                show = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { show = false }
            }
    }
}

// MARK: - Stats
func streakDays(_ records: [WorkoutRecord]) -> Int {
    let cal = Calendar.current
    let active = Set(records.map { cal.startOfDay(for: $0.date) })
    var day = cal.startOfDay(for: .now)
    if !active.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
    var n = 0
    while active.contains(day) { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
    return n
}

func weekMinutes(_ records: [WorkoutRecord]) -> Int {
    let cal = Calendar.current
    let from = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now))!
    return Int(records.filter { $0.date >= from }.map(\.duration).reduce(0, +) / 60)
}

// MARK: - Daily quests
func todayMinutes(_ records: [WorkoutRecord]) -> Double {
    records.filter { Calendar.current.isDateInToday($0.date) }.map(\.duration).reduce(0, +) / 60
}

func waterToday() -> Int {
    guard let d = UserDefaults.standard.data(forKey: "waterLog"),
          let l = try? JSONDecoder().decode([String: Int].self, from: d) else { return 0 }
    return l[dayKey(), default: 0]
}

func calmToday(_ records: [WorkoutRecord]) -> Int {
    records.filter { Calendar.current.isDateInToday($0.date) && ($0.type == "Meditation" || $0.type == "Stretching") }.count
}

func questsDone(_ records: [WorkoutRecord]) -> Int {
    var n = 0
    if todayMinutes(records) >= 20 { n += 1 }
    if waterToday() >= ud("waterGoal", 2000) { n += 1 }
    if calmToday(records) >= 1 { n += 1 }
    return n
}

struct QuestsCard: View {
    @EnvironmentObject var conn: ConnectivityManager
    @State private var tick = 0

    struct Quest: Identifiable {
        let id: String
        let title: String, icon: String
        let color: Color
        let value: Double, goal: Double
        var done: Bool { value >= goal }
    }

    var quests: [Quest] {
        _ = tick
        return [
            Quest(id: "move", title: "Move 20 min", icon: "figure.run", color: Theme.exercise,
                  value: todayMinutes(conn.records), goal: 20),
            Quest(id: "water", title: "Water goal", icon: "drop.fill", color: Theme.stand,
                  value: Double(waterToday()), goal: Double(ud("waterGoal", 2000))),
            Quest(id: "calm", title: "Meditate or stretch", icon: "leaf.fill", color: Theme.move,
                  value: Double(calmToday(conn.records)), goal: 1),
        ]
    }
    var doneCount: Int { quests.filter(\.done).count }

    var body: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Today's quests").font(.headline)
                    Spacer()
                    Text("\(doneCount)/\(quests.count)").font(.system(.headline, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(doneCount == quests.count ? Theme.exercise : Color.secondary)
                }
                ForEach(quests) { q in
                    HStack(spacing: 12) {
                        Image(systemName: q.done ? "checkmark.circle.fill" : q.icon)
                            .font(.title3).foregroundStyle(q.done ? Theme.exercise : q.color).frame(width: 28)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: q.done)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(q.title).font(.subheadline.weight(.semibold))
                                .strikethrough(q.done, color: .secondary)
                            ProgressView(value: min(q.value, q.goal), total: q.goal).tint(q.color)
                        }
                    }
                }
            }
            .animation(.spring(duration: 0.5), value: doneCount)
        }
        .confetti(trigger: doneCount == 3)
        .onAppear { tick += 1 }
    }
}

// MARK: - Friends (no server: friend codes)
struct Friend: Codable, Identifiable {
    var id: String
    var name: String
    var emoji: String
    var minutes: Int
    var streak: Int
    var sessions: Int
    var updated: Date
}

struct SharedCode: Codable {
    var i: String      // user ID
    var n: String      // name
    var e: String      // emoji
    var m: Int         // minutes in the last 7 days
    var s: Int         // streak in days
    var c: Int         // session count
    var t: Date        // created at
}

final class FriendsStore: ObservableObject {
    @Published var friends: [Friend] = []
    private let key = "friendsList"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let f = try? JSONDecoder().decode([Friend].self, from: d) { friends = f }
    }

    var myId: String {
        if let s = UserDefaults.standard.string(forKey: "myFriendId") { return s }
        let n = UUID().uuidString
        UserDefaults.standard.set(n, forKey: "myFriendId")
        return n
    }

    func makeCode(name: String, emoji: String, records: [WorkoutRecord]) -> String {
        let c = SharedCode(i: myId, n: name, e: emoji, m: weekMinutes(records),
                           s: streakDays(records), c: records.count, t: .now)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let d = try? enc.encode(c) else { return "" }
        return "MOVEIO-" + d.base64EncodedString()
    }

    func add(_ input: String) -> (ok: Bool, text: String) {
        let flat = input.filter { !$0.isWhitespace }
        guard let r = flat.range(of: "MOVEIO-") else { return (false, "Invalid code.") }
        let payload = String(flat[r.upperBound...].prefix(while: {
            $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "="
        }))
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let data = Data(base64Encoded: payload),
              let c = try? dec.decode(SharedCode.self, from: data) else { return (false, "Invalid code.") }
        if c.i == myId { return (false, "This is your own code.") }
        let f = Friend(id: c.i, name: c.n, emoji: c.e, minutes: c.m, streak: c.s, sessions: c.c, updated: c.t)
        if let idx = friends.firstIndex(where: { $0.id == f.id }) {
            friends[idx] = f; save()
            return (true, "Updated: \(f.name)")
        }
        friends.append(f); save()
        return (true, "Added: \(f.name)")
    }

    func remove(_ id: String) { friends.removeAll { $0.id == id }; save() }
    private func save() {
        if let d = try? JSONEncoder().encode(friends) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct LeaderRow: Identifiable {
    let id: String
    let name: String, emoji: String
    let minutes: Int, streak: Int
    let isMe: Bool
    let updated: Date?
}

struct BarRow: View {
    let rank: Int
    let r: LeaderRow
    let maxMin: Int
    @State private var shown = false

    var body: some View {
        HStack(spacing: 10) {
            Text(rank <= 3 ? ["🥇", "🥈", "🥉"][rank - 1] : "\(rank)")
                .font(.title3).frame(width: 30)
            Text(r.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(r.isMe ? "\(r.name) (you)" : r.name).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(r.minutes) min").font(.subheadline).monospacedDigit()
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule().fill(r.isMe ? Theme.move : Theme.stand)
                            .frame(width: shown ? g.size.width * CGFloat(r.minutes) / CGFloat(max(maxMin, 1)) : 0)
                    }
                }
                .frame(height: 8)
                HStack(spacing: 4) {
                    Label("\(r.streak) d", systemImage: "flame.fill").foregroundStyle(Color.orange)
                    if let u = r.updated {
                        Text("· updated \(u.formatted(.relative(presentation: .named)))")
                    }
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.2).delay(Double(rank) * 0.08)) { shown = true }
        }
        .animation(.spring(duration: 0.7), value: r.minutes)
    }
}

struct FriendsView: View {
    @EnvironmentObject var conn: ConnectivityManager
    @EnvironmentObject var profile: ProfileStore
    @StateObject private var store = FriendsStore()
    @AppStorage("myEmoji") private var myEmoji = "😎"
    @State private var input = ""
    @State private var message = ""
    @State private var messageOK = true
    @State private var celebrate = false
    @State private var copied = false

    let emojis = ["😎", "🏃", "🦊", "🐼", "🦁", "🐯", "🐵", "🦄", "🔥", "⚡️", "🌟", "🧘"]

    var myName: String { profile.name.isEmpty ? "Tu" : profile.name }
    var rows: [LeaderRow] {
        let me = LeaderRow(id: "me", name: myName, emoji: myEmoji, minutes: weekMinutes(conn.records),
                           streak: streakDays(conn.records), isMe: true, updated: nil)
        let others = store.friends.map {
            LeaderRow(id: $0.id, name: $0.name, emoji: $0.emoji, minutes: $0.minutes, streak: $0.streak,
                      isMe: false, updated: $0.updated)
        }
        return ([me] + others).sorted { $0.minutes != $1.minutes ? $0.minutes > $1.minutes : $0.name < $1.name }
    }
    var iAmLeader: Bool { rows.count > 1 && rows.first?.isMe == true }
    var code: String { store.makeCode(name: myName, emoji: myEmoji, records: conn.records) }
    var shareText: String { "Join me on Moveio! Paste this code in the Friends tab:\n\(code)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    challengeCard
                    boardCard
                    mineCard
                    addCard
                    Text("Friend stats only update when your friend sends you a new code. The app has no server, so nothing syncs automatically.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }.padding()
            }
            .confetti(trigger: iAmLeader || celebrate)
            .navigationTitle("Friends")
        }
    }

    var challengeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Weekly challenge").font(.headline)
                    Spacer()
                    Image(systemName: "trophy.fill").foregroundStyle(Color.yellow)
                        .symbolEffect(.bounce, value: iAmLeader)
                }
                if rows.count < 2 {
                    Text("Add friends and compete to see who moves the most this week.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if iAmLeader {
                    Text("You're in first place! You're \(rows[0].minutes - rows[1].minutes) min ahead of \(rows[1].name).")
                        .font(.subheadline)
                } else if let lead = rows.first, let me = rows.first(where: \.isMe) {
                    Text("\(lead.name) is \(lead.minutes - me.minutes) min ahead. You can catch up!")
                        .font(.subheadline)
                }
            }
        }
    }

    var boardCard: some View {
        let maxMin = rows.map(\.minutes).max() ?? 1
        return card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Last 7 days").font(.headline)
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    BarRow(rank: i + 1, r: r, maxMin: maxMin)
                        .contextMenu {
                            if !r.isMe {
                                Button("Remove friend", role: .destructive) {
                                    withAnimation(.spring) { store.remove(r.id) }
                                }
                            }
                        }
                }
            }
            .animation(.spring(duration: 0.6), value: rows.map(\.id))
        }
    }

    var mineCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("My friend profile").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(emojis, id: \.self) { e in
                            Text(e).font(.title).padding(6)
                                .background(myEmoji == e ? Theme.move.opacity(0.2) : Color.clear, in: Circle())
                                .scaleEffect(myEmoji == e ? 1.15 : 1)
                                .onTapGesture { withAnimation(.spring(duration: 0.4, bounce: 0.4)) { myEmoji = e } }
                        }
                    }
                }
                ShareLink(item: shareText) { Label("Share my code", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderedProminent).tint(Theme.move)
                Button {
                    UIPasteboard.general.string = shareText
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copied = false } }
                } label: {
                    Label(copied ? "Copied!" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }.buttonStyle(.bordered)
            }
        }
    }

    var addCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add a friend").font(.headline)
                TextField("Paste your friend's code", text: $input, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Paste") { input = UIPasteboard.general.string ?? "" }.buttonStyle(.bordered)
                    Button("Add") { addFriend() }
                        .buttonStyle(.borderedProminent).tint(Theme.move).disabled(input.isEmpty)
                }
                if !message.isEmpty {
                    Label(message, systemImage: messageOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(messageOK ? Theme.exercise : Color.orange)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring, value: message)
        }
    }

    func addFriend() {
        let r = store.add(input)
        messageOK = r.ok; message = r.text
        if r.ok {
            input = ""
            withAnimation(.spring) { }
            celebrate = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { celebrate = false }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
