import HealthKit

final class HealthManager {
    static let shared = HealthManager()

    private let healthStore = HKHealthStore()

    private init() { }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            return
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        try await healthStore.requestAuthorization(
            toShare: typesToShare,
            read: typesToRead
        )
    }
}
