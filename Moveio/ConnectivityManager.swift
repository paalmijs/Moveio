// Add to BOTH targets (iPhone + Watch)
import Foundation
import Combine
import WatchConnectivity

final class ConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = ConnectivityManager()
    @Published var records: [WorkoutRecord] = []
    @Published var watchStatus = "Checking..."
    private let key = "records"
    private let pendingKey = "pendingRecords"
    private var pending: [WorkoutRecord] = []

    // Old Latvian type names -> English
    static let legacy: [String: String] = [
        "Skriešana": "Running", "Soļošana": "Walking", "Riteņbraukšana": "Cycling",
        "Spēka treniņš": "Strength", "Meditācija": "Meditation", "Joga": "Yoga",
        "Peldēšana": "Swimming", "Cits": "Other"
    ]
    static func normalize(_ t: String) -> String { legacy[t] ?? t }

    override init() {
        super.init()
        load(); loadPending()
        guard WCSession.isSupported() else { watchStatus = "Not supported"; return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Touch this at app launch so the session is already active when a workout ends.
    func start() {}

    func add(_ r: WorkoutRecord) {
        records.insert(r, at: 0); save()
        #if os(watchOS)
        pending.append(r); savePending(); flush()
        #endif
    }

    func remove(ids: [UUID]) {
        records.removeAll { ids.contains($0.id) }; save()
    }

    // MARK: Persistence
    private func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let r = try? JSONDecoder().decode([WorkoutRecord].self, from: d) {
            records = r.map { var x = $0; x.type = Self.normalize(x.type); return x }
            save()
        }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(records) { UserDefaults.standard.set(d, forKey: key) }
    }
    private func loadPending() {
        if let d = UserDefaults.standard.data(forKey: pendingKey),
           let r = try? JSONDecoder().decode([WorkoutRecord].self, from: d) { pending = r }
    }
    private func savePending() {
        if let d = try? JSONEncoder().encode(pending) { UserDefaults.standard.set(d, forKey: pendingKey) }
    }

    // MARK: WCSessionDelegate
    func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        #if os(watchOS)
        DispatchQueue.main.async { self.flush() }
        #else
        updateStatus(s)
        #endif
    }

    #if os(watchOS)
    /// Sends everything that has not been delivered yet. Called after each workout and when the session activates.
    func flush() {
        let s = WCSession.default
        guard s.activationState == .activated else { return }   // stays queued, sent on activation
        let enc = JSONEncoder()

        // One time: also send workouts recorded before syncing was fixed.
        if !UserDefaults.standard.bool(forKey: "historyResent") {
            for r in records.prefix(200) {
                if let d = try? enc.encode(r) { s.transferUserInfo(["record": d]) }
            }
            UserDefaults.standard.set(true, forKey: "historyResent")
        }
        for r in pending {
            guard let d = try? enc.encode(r) else { continue }
            s.transferUserInfo(["record": d])                    // guaranteed, queued delivery
            if s.isReachable { s.sendMessage(["record": d], replyHandler: nil, errorHandler: nil) } // instant if phone is open
        }
        pending.removeAll(); savePending()
    }
    #endif

    #if os(iOS)
    func sessionDidBecomeInactive(_ s: WCSession) {}
    func sessionDidDeactivate(_ s: WCSession) { s.activate() }
    func sessionWatchStateDidChange(_ s: WCSession) { updateStatus(s) }
    func sessionReachabilityDidChange(_ s: WCSession) { updateStatus(s) }

    func session(_ s: WCSession, didReceiveUserInfo userInfo: [String: Any]) { receive(userInfo) }
    func session(_ s: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }

    private func receive(_ info: [String: Any]) {
        guard let d = info["record"] as? Data,
              var r = try? JSONDecoder().decode(WorkoutRecord.self, from: d) else { return }
        r.type = Self.normalize(r.type)
        DispatchQueue.main.async {
            if !self.records.contains(where: { $0.id == r.id }) {
                self.records.insert(r, at: 0)
                self.records.sort { $0.date > $1.date }
                self.save()
            }
        }
    }

    private func updateStatus(_ s: WCSession) {
        let text: String
        if !s.isPaired { text = "No Apple Watch paired" }
        else if !s.isWatchAppInstalled { text = "Moveio isn't installed on your Watch" }
        else if s.isReachable { text = "Apple Watch connected" }
        else { text = "Apple Watch paired. Syncs when it's nearby" }
        DispatchQueue.main.async { self.watchStatus = text }
    }
    #endif
}
