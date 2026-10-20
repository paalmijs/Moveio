// iPhone target only (new file)
import SwiftUI
import Charts
import MapKit
import CoreLocation

// MARK: - Route data
struct RoutePoint: Codable {
    var lat: Double, lon: Double, alt: Double, t: Double   // t = seconds since 1970
    init(_ l: CLLocation) {
        lat = l.coordinate.latitude; lon = l.coordinate.longitude
        alt = l.altitude; t = l.timestamp.timeIntervalSince1970
    }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
}

/// Routes live in files on the iPhone (one JSON file per workout).
enum RouteStore {
    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("routes", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).json") }
    static func save(_ p: [RoutePoint], id: UUID) {
        if let d = try? JSONEncoder().encode(p) { try? d.write(to: url(id), options: .atomic) }
    }
    static func load(_ id: UUID) -> [RoutePoint] {
        guard let d = try? Data(contentsOf: url(id)),
              let p = try? JSONDecoder().decode([RoutePoint].self, from: d) else { return [] }
        return p
    }
    static func exists(_ id: UUID) -> Bool { FileManager.default.fileExists(atPath: url(id).path) }
    static func delete(_ id: UUID) { try? FileManager.default.removeItem(at: url(id)) }
    static func deleteAll() { try? FileManager.default.removeItem(at: dir) }
}

// MARK: - Route analysis (splits, elevation)
struct Split: Identifiable {
    let id: Int
    let meters: Double
    let seconds: Double
    var secPerKm: Double { seconds / (meters / 1000) }
    var kmh: Double { (meters / 1000) / (seconds / 3600) }
}

struct RouteStats {
    var distance = 0.0
    var duration = 0.0
    var gain = 0.0
    var splits: [Split] = []

    init(_ pts: [RoutePoint]) {
        guard pts.count > 1 else { return }
        duration = pts.last!.t - pts.first!.t

        var accM = 0.0, accT = 0.0
        for i in 1..<pts.count {
            var d = pts[i - 1].location.distance(from: pts[i].location)
            var dt = max(pts[i].t - pts[i - 1].t, 0)
            distance += d
            while accM + d >= 1000, d > 0 {
                let part = (1000 - accM) / d
                splits.append(Split(id: splits.count + 1, meters: 1000, seconds: accT + dt * part))
                d *= (1 - part); dt *= (1 - part)
                accM = 0; accT = 0
            }
            accM += d; accT += dt
        }
        if accM > 100 { splits.append(Split(id: splits.count + 1, meters: accM, seconds: accT)) }

        // smooth GPS altitude, then add up the climbs
        let alts = pts.map(\.alt)
        let w = 5
        let smooth = alts.indices.map { i -> Double in
            let lo = max(0, i - w / 2), hi = min(alts.count - 1, i + w / 2)
            return alts[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
        for i in 1..<smooth.count where smooth[i] > smooth[i - 1] { gain += smooth[i] - smooth[i - 1] }
    }
}

func paceString(_ secPerKm: Double) -> String {
    guard secPerKm.isFinite, secPerKm > 0 else { return "--" }
    return String(format: "%d:%02d", Int(secPerKm) / 60, Int(secPerKm) % 60)
}

func gpxText(name: String, points: [RoutePoint]) -> String {
    let f = ISO8601DateFormatter()
    var s = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="Moveio" xmlns="http://www.topografix.com/GPX/1/1">
    <trk><name>\(name)</name><trkseg>

    """
    for p in points {
        s += "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><ele>\(String(format: "%.1f", p.alt))</ele><time>\(f.string(from: Date(timeIntervalSince1970: p.t)))</time></trkpt>\n"
    }
    s += "</trkseg></trk></gpx>\n"
    return s
}

// MARK: - Map
struct RouteMap: View {
    let points: [RoutePoint]
    var follow = false

    private var coords: [CLLocationCoordinate2D] { points.map(\.coordinate) }

    private var rect: MKMapRect {
        guard !coords.isEmpty else { return .world }
        var r = MKMapRect.null
        for c in coords { r = r.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 0, height: 0))) }
        let padX = max(r.width * 0.25, 250), padY = max(r.height * 0.25, 250)
        return r.insetBy(dx: -padX, dy: -padY)
    }

    var body: some View {
        Group {
            if follow {
                Map(initialPosition: .userLocation(fallback: .automatic)) {
                    UserAnnotation()
                    if coords.count > 1 { MapPolyline(coordinates: coords).stroke(Theme.move, lineWidth: 5) }
                }
            } else {
                Map(initialPosition: .rect(rect)) {
                    if coords.count > 1 { MapPolyline(coordinates: coords).stroke(Theme.move, lineWidth: 5) }
                    if let f = coords.first { Marker("Start", systemImage: "play.fill", coordinate: f).tint(Theme.exercise) }
                    if let l = coords.last, coords.count > 1 { Marker("Finish", systemImage: "flag.checkered", coordinate: l).tint(.red) }
                }
            }
        }
        .mapStyle(.standard)
    }
}

// MARK: - History row
struct HistoryRow: View {
    let r: WorkoutRecord
    var body: some View {
        let s = style(for: r.type)
        HStack(spacing: 12) {
            Image(systemName: s.icon).foregroundStyle(.white).font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36).background(s.color.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(r.type).font(.headline)
                    if RouteStore.exists(r.id) { Image(systemName: "map.fill").font(.caption).foregroundStyle(.secondary) }
                }
                Text(r.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(r.duration / 60)) min").font(.system(.headline, design: .rounded))
                let parts = [r.distance > 0 ? String(format: "%.2f km", r.distance / 1000) : nil,
                             r.calories > 0 ? "\(Int(r.calories)) kcal" : nil,
                             r.avgHeartRate > 0 ? "\(Int(r.avgHeartRate)) bpm" : nil].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Activity detail (Strava style)
struct ActivityDetailView: View {
    let record: WorkoutRecord
    @State private var points: [RoutePoint] = []
    @State private var gpx: URL?

    var stats: RouteStats { RouteStats(points) }
    var isCycling: Bool { record.type == "Cycling" }
    var hasRoute: Bool { points.count > 1 }

    var distance: Double { record.distance > 0 ? record.distance : stats.distance }

    var metrics: [(String, String, String)] {
        var m: [(String, String, String)] = []
        if distance > 0 { m.append(("Distance", String(format: "%.2f", distance / 1000), "km")) }
        m.append(("Time", hmsString(record.duration), ""))
        if distance > 50, record.duration > 0 {
            if isCycling { m.append(("Avg speed", String(format: "%.1f", (distance / 1000) / (record.duration / 3600)), "km/h")) }
            else { m.append(("Avg pace", paceString(record.duration / (distance / 1000)), "min/km")) }
        }
        if record.calories > 0 { m.append(("Calories", "\(Int(record.calories))", "kcal")) }
        if hasRoute, stats.gain > 0 { m.append(("Elevation", "\(Int(stats.gain))", "m gain")) }
        if record.avgHeartRate > 0 { m.append(("Avg heart rate", "\(Int(record.avgHeartRate))", "bpm")) }
        return m
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if hasRoute {
                    RouteMap(points: points)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    card {
                        VStack(spacing: 8) {
                            Image(systemName: "map").font(.largeTitle).foregroundStyle(.secondary)
                            Text("No route for this workout").font(.headline)
                            Text("Routes are recorded when you start a GPS workout (Running, Walking, Cycling) on your iPhone.")
                                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.0).font(.caption).foregroundStyle(.secondary)
                            Text(m.1).font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                                .minimumScaleFactor(0.6).lineLimit(1)
                            if !m.2.isEmpty { Text(m.2).font(.caption).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

                if hasRoute, !stats.splits.isEmpty { splitsCard }

                if let gpx {
                    ShareLink(item: gpx) { Label("Export GPX (Strava, Garmin...)", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered).tint(Theme.move)
                }
            }
            .padding()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(record.type)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            points = RouteStore.load(record.id)
            if points.count > 1 {
                let name = "\(record.type) \(record.date.formatted(date: .abbreviated, time: .shortened))"
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Moveio-\(record.type)-\(Int(record.date.timeIntervalSince1970)).gpx")
                try? gpxText(name: name, points: points).write(to: url, atomically: true, encoding: .utf8)
                gpx = url
            }
        }
    }

    var splitsCard: some View {
        let splits = stats.splits
        let best = splits.filter { $0.meters >= 900 }.map { isCycling ? $0.kmh : -$0.secPerKm }.max()
        let values = splits.map { isCycling ? $0.kmh : $0.secPerKm }
        let maxV = values.max() ?? 1
        return card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Splits").font(.headline)
                ForEach(splits) { s in
                    let v = isCycling ? s.kmh : s.secPerKm
                    // for pace: a shorter bar means slower, so invert the scale
                    let frac = isCycling ? v / maxV : 1 - (v - (values.min() ?? v)) / max(maxV - (values.min() ?? v), 1) * 0.6
                    let isBest = best != nil && (isCycling ? s.kmh : -s.secPerKm) == best && s.meters >= 900
                    HStack(spacing: 10) {
                        Text(s.meters >= 990 ? "\(s.id)" : String(format: "%.2f", s.meters / 1000))
                            .font(.caption.weight(.semibold)).frame(width: 34, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(isBest ? Theme.exercise : Theme.move)
                                .frame(width: g.size.width * CGFloat(min(max(frac, 0.15), 1)))
                        }.frame(height: 10)
                        Text(isCycling ? String(format: "%.1f", s.kmh) : paceString(s.secPerKm))
                            .font(.system(.footnote, design: .rounded).weight(.semibold)).monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Text(isCycling ? "km/h per km" : "min/km per km. Green is your fastest split.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
