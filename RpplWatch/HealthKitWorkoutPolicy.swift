import Foundation
import HealthKit

/// Watch production HealthKit workout configuration (DCS-44: waterSports MET model).
enum HealthKitWorkoutPolicy {
    static var activityType: HKWorkoutActivityType { .waterSports }

    static func makeConfiguration() -> HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        // waterSports MET model for wakeboarding. Fitness may omit distance/speed tiles (DCS-44).
        config.activityType = activityType
        config.locationType = .outdoor
        return config
    }
}
