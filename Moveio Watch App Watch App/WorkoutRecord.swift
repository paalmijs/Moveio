import Foundation

struct WorkoutRecord: Codable, Identifiable {
    var id = UUID()
    var type: String
    var date: Date
    var duration: TimeInterval
    var calories: Double
    var avgHeartRate: Double
    var distance: Double
}
