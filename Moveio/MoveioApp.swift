// iPhone target only. Paste over MoveioApp.swift
import SwiftUI
import Charts

@main
struct MoveioApp: App {
    @StateObject var conn = ConnectivityManager.shared
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(conn)
                .environment(\.locale, Locale(identifier: "en_US"))
        }
    }
}

func style(for type: String) -> (icon: String, color: Color) {
    switch type {
    case "Running": return ("figure.run", Theme.move)
    case "Walking": return ("figure.walk", Theme.exercise)
    case "Cycling": return ("figure.outdoor.cycle", Theme.stand)
    case "Strength": return ("dumbbell.fill", .orange)
    case "HIIT": return ("flame.fill", .red)
    case "Yoga": return ("figure.yoga", .purple)
    case "Swimming": return ("figure.pool.swim", .blue)
    case "Meditation": return ("leaf.fill", .mint)
    case "Pomodoro": return ("timer", .orange)
    case "Stretching": return ("figure.flexibility", .purple)
    default: return ("sparkles", .yellow)
    }
}

struct RootView: View {
    @StateObject private var profile = ProfileStore.shared
    var body: some View {
        Group {
            if profile.onboarded {
                TabView {
                    OverviewView().tabItem { Label("Summary", systemImage: "chart.bar.fill") }
                    HistoryView().tabItem { Label("History", systemImage: "clock.fill") }
                    ToolsView().tabItem { Label("Tools", systemImage: "square.grid.2x2.fill") }
                    FriendsView().tabItem { Label("Friends", systemImage: "person.2.fill") }
                    ProfileView().tabItem { Label("Profile", systemImage: "person.fill") }
                }
                .tint(Theme.move)
            } else {
                OnboardingView()
            }
        }
        .environmentObject(profile)
        .environment(\.locale, Locale(identifier: "en_US"))
    }
}

// MARK: - Summary
struct DayStat: Identifiable {
    let date: Date, minutes: Double
    var id: Date { date }
}

struct OverviewView: View {
    @EnvironmentObject var conn: ConnectivityManager
    @AppStorage("weeklyGoal") private var goal = 150
    @State private var tick = 0
    private let cal = Calendar.current

    var week: [WorkoutRecord] {
        let from = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now))!
        return conn.records.filter { $0.date >= from }
    }
    var minutes: Double { week.map(\.duration).reduce(0, +) / 60 }
    var dailyGoal: Double { max(Double(goal) / 7, 1) }
    var questCount: Int { _ = tick; return questsDone(conn.records) }
    var days: [DayStat] {
        (0..<7).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: .now))!
            let m = week.filter { cal.isDate($0.date, inSameDayAs: d) }.map(\.duration).reduce(0, +) / 60
            return DayStat(date: d, minutes: m)
        }
    }
    var byType: [(String, Double)] {
        Dictionary(grouping: week, by: \.type).map { ($0.key, $0.value.map(\.duration).reduce(0, +) / 60) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StartWorkoutCard()
                    card {
                        VStack(spacing: 16) {
                            HStack(spacing: 18) {
                                TripleRing(outer: minutes / Double(goal),
                                           middle: todayMinutes(conn.records) / dailyGoal,
                                           inner: Double(questCount) / 3)
                                    .frame(width: 136, height: 136)
                                VStack(alignment: .leading, spacing: 10) {
                                    legend("Move", "\(Int(minutes))/\(goal) min this week", Theme.move)
                                    legend("Exercise", "\(Int(todayMinutes(conn.records)))/\(Int(dailyGoal)) min today", Theme.exercise)
                                    legend("Quests", "\(questCount)/3 today", Theme.stand)
                                }
                                Spacer(minLength: 0)
                            }
                            Divider()
                            HStack {
                                chip("flame.fill", "\(streakDays(conn.records))", "day streak", .orange)
                                chip("figure.run", "\(week.count)", "sessions", Theme.exercise)
                                chip("bolt.fill", "\(Int(week.map(\.calories).reduce(0, +)))", "kcal", Theme.move)
                            }
                        }
                    }
                    QuestsCard()
                    HealthCard()
                    card {
                        VStack(alignment: .leading) {
                            Text("Last 7 days").font(.headline)
                            Chart(days) { d in
                                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Min", d.minutes))
                                    .foregroundStyle(Theme.exercise.gradient).cornerRadius(5)
                            }
                            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                            .frame(height: 150)
                        }
                    }
                    CalendarCard()
                    if !byType.isEmpty {
                        card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("By activity").font(.headline)
                                ForEach(byType, id: \.0) { t, m in
                                    HStack {
                                        Image(systemName: style(for: t).icon).foregroundStyle(style(for: t).color).frame(width: 28)
                                        Text(t)
                                        Spacer()
                                        Text("\(Int(m)) min").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Start a session on your watch and your data will show up here.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 20)
                    }
                }.padding()
            }
            .background(Theme.bg.ignoresSafeArea())
            .confetti(trigger: minutes >= Double(goal) && minutes > 0)
            .navigationTitle("Summary")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { AchievementsView() } label: { Image(systemName: "trophy.fill").foregroundStyle(.yellow) }
                }
            }
            .onAppear { tick += 1 }
        }
    }

    func legend(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(c)
            Text(v).font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
        }
    }

    func chip(_ icon: String, _ v: String, _ label: String, _ c: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).foregroundStyle(c).symbolEffect(.bounce, value: v)
            Text(v).font(.system(.title3, design: .rounded).weight(.bold)).contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

// MARK: - History
struct HistoryView: View {
    @EnvironmentObject var conn: ConnectivityManager
    @State private var filter: String?
    @State private var showAdd = false

    var types: [String] { Array(Set(conn.records.map(\.type))).sorted() }
    var filtered: [WorkoutRecord] { conn.records.filter { filter == nil || $0.type == filter } }

    var body: some View {
        NavigationStack {
            List {
                if !types.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            chip("All", nil)
                            ForEach(types, id: \.self) { chip($0, $0) }
                        }
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                ForEach(filtered) { r in
                    NavigationLink { ActivityDetailView(record: r) } label: { HistoryRow(r: r) }
                }
                .onDelete { idx in
                    let ids = idx.map { filtered[$0].id }
                    ids.forEach { RouteStore.delete($0) }
                    conn.remove(ids: ids)
                }
            }
            .overlay { if conn.records.isEmpty { Text("No sessions yet").foregroundStyle(.secondary) } }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: csvText(conn.records)) { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { ManualLogView() }
        }
    }

    func chip(_ t: String, _ value: String?) -> some View {
        Button { withAnimation(.spring) { filter = value } } label: {
            Text(t).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 7)
                .background(filter == value ? Theme.move : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(filter == value ? Color.white : Color.primary)
        }.buttonStyle(.plain)
    }
}
