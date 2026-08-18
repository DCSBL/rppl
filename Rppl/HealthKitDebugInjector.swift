import CoreLocation
import Foundation
import HealthKit
import RpplCore

/// Saves a bundled real-session export into HealthKit for Fitness UI inspection (DCS-39 debug).
@MainActor
enum HealthKitDebugInjector {
    private static let fixtureBaseName = "HealthKitInjectFixture"

    enum InjectError: LocalizedError {
        case healthUnavailable
        case missingFixture
        case decodeFailed(String)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .healthUnavailable:
                return "HealthKit is not available on this device."
            case .missingFixture:
                return "Bundled fixture HealthKitInjectFixture.json not found."
            case .decodeFailed(let detail):
                return "Could not decode fixture: \(detail)"
            case .saveFailed(let detail):
                return "HealthKit save failed: \(detail)"
            }
        }
    }

    enum Style: String, Sendable {
        /// Ride + following dock wait as one activity; motionPaused on rest (first inject).
        case ridePlusRest
        /// Alternating riding / inactive activities. No motion pause events.
        case workRest
        /// One activity per ride window only. No motion pause events.
        case rideOnly
        /// Samples + route only. No intervals, no motion events.
        case samplesOnly
    }

    struct RoundWindow: Sendable {
        var start: Date
        var end: Date
        var code: String
    }

    static func inject(healthStore: HKHealthStore, style: Style) async throws -> String {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw InjectError.healthUnavailable
        }

        let package = try loadFixture()
        let stats = SessionStatsBuilder.build(
            manifest: package.manifest,
            detections: package.detections,
            locations: package.locations,
            health: package.health
        )
        let sessionStart = package.manifest.startedAt
        let sessionEnd = package.manifest.endedAt ?? stats.endedAt
        let rounds = windows(style: style, rides: stats.rides, sessionEnd: sessionEnd)

        let config = HKWorkoutConfiguration()
        config.activityType = .waterSports
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: config,
            device: .local()
        )

        try await beginCollection(builder: builder, at: sessionStart)

        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: false,
            HKMetadataKeyWorkoutBrandName: "Rppl",
            "nl.dcsbl.rppl.debugInject": true,
            "nl.dcsbl.rppl.injectStyle": style.rawValue,
            "nl.dcsbl.rppl.sourceSessionId": package.manifest.sessionId,
            "nl.dcsbl.rppl.activityName": "Cable Park (\(style.rawValue))",
        ]
        if stats.ridingDuration > 0, stats.totalDistanceMeters > 0 {
            let speedMps = stats.totalDistanceMeters / stats.ridingDuration
            metadata[HKMetadataKeyAverageSpeed] = HKQuantity(unit: .meter().unitDivided(by: .second()), doubleValue: speedMps)
        }
        try await addMetadata(metadata, builder: builder)

        try await addHeartRateSamples(from: package.health, builder: builder)
        try await addEnergySamples(from: package.health, builder: builder)
        try await addRideDistanceSamples(rides: stats.rides, builder: builder)
        try await addRoundEncodings(
            style: style,
            rounds: rounds,
            rides: stats.rides,
            config: config,
            builder: builder
        )

        try await endCollection(builder: builder, at: sessionEnd)
        let workout = try await finishWorkout(builder: builder)
        try await saveRoute(locations: package.locations, workout: workout, healthStore: healthStore)

        let durationMin = Int(sessionEnd.timeIntervalSince(sessionStart) / 60)
        return "Saved \(style.rawValue) · \(rounds.count) intervals · \(stats.rideCount) rides · \(durationMin) min"
    }

    private static func loadFixture() throws -> SessionTransferPackage {
        guard let url = Bundle.main.url(forResource: fixtureBaseName, withExtension: "json") else {
            throw InjectError.missingFixture
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SessionTransferPackage.self, from: data)
        } catch {
            throw InjectError.decodeFailed(error.localizedDescription)
        }
    }

    private static func windows(
        style: Style,
        rides: [RideSegmentStats],
        sessionEnd: Date
    ) -> [RoundWindow] {
        switch style {
        case .samplesOnly:
            return []
        case .rideOnly:
            return rides.map { RoundWindow(start: $0.startedAt, end: $0.endedAt, code: DetectionCodes.riding) }
        case .ridePlusRest:
            return rides.enumerated().map { index, ride in
                let end = index + 1 < rides.count ? rides[index + 1].startedAt : sessionEnd
                return RoundWindow(start: ride.startedAt, end: end, code: DetectionCodes.riding)
            }
        case .workRest:
            var result: [RoundWindow] = []
            for (index, ride) in rides.enumerated() {
                result.append(RoundWindow(start: ride.startedAt, end: ride.endedAt, code: DetectionCodes.riding))
                let restEnd = index + 1 < rides.count ? rides[index + 1].startedAt : sessionEnd
                if restEnd > ride.endedAt {
                    result.append(
                        RoundWindow(start: ride.endedAt, end: restEnd, code: DetectionCodes.inactive)
                    )
                }
            }
            return result
        }
    }

    private static func beginCollection(builder: HKWorkoutBuilder, at start: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: start) { success, error in
                if let error {
                    continuation.resume(throwing: InjectError.saveFailed(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InjectError.saveFailed("beginCollection failed"))
                }
            }
        }
    }

    private static func endCollection(builder: HKWorkoutBuilder, at end: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: end) { success, error in
                if let error {
                    continuation.resume(throwing: InjectError.saveFailed(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InjectError.saveFailed("endCollection failed"))
                }
            }
        }
    }

    private static func finishWorkout(builder: HKWorkoutBuilder) async throws -> HKWorkout {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKWorkout, Error>) in
            builder.finishWorkout { workout, error in
                if let error {
                    continuation.resume(throwing: InjectError.saveFailed(error.localizedDescription))
                } else if let workout {
                    continuation.resume(returning: workout)
                } else {
                    continuation.resume(throwing: InjectError.saveFailed("finishWorkout returned no workout"))
                }
            }
        }
    }

    private static func addMetadata(_ metadata: [String: Any], builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.addMetadata(metadata) { success, error in
                if let error {
                    continuation.resume(throwing: InjectError.saveFailed(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InjectError.saveFailed("addMetadata failed"))
                }
            }
        }
    }

    private static func addWorkoutEvents(_ events: [HKWorkoutEvent], builder: HKWorkoutBuilder) async throws {
        guard !events.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.addWorkoutEvents(events) { success, error in
                if let error {
                    continuation.resume(throwing: InjectError.saveFailed(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InjectError.saveFailed("addWorkoutEvents failed"))
                }
            }
        }
    }

    private static func addSamples(_ samples: [HKSample], builder: HKWorkoutBuilder) async throws {
        guard !samples.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.add(samples) { success, error in
                if let error {
                    continuation.resume(throwing: InjectError.saveFailed(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InjectError.saveFailed("add samples failed"))
                }
            }
        }
    }

    private static func addHeartRateSamples(from health: [HealthMetricSample], builder: HKWorkoutBuilder) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples: [HKQuantitySample] = health.compactMap { row in
            guard let bpm = row.heartRateBPM else { return nil }
            let quantity = HKQuantity(unit: unit, doubleValue: bpm)
            return HKQuantitySample(type: type, quantity: quantity, start: row.timestamp, end: row.timestamp)
        }
        try await addSamples(samples, builder: builder)
    }

    private static func addEnergySamples(from health: [HealthMetricSample], builder: HKWorkoutBuilder) async throws {
        guard let activeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) else { return }
        let kcal = HKUnit.kilocalorie()
        var samples: [HKQuantitySample] = []
        var lastActive = 0.0
        var lastBasal = 0.0
        for row in health.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let active = row.activeEnergyKilocalories {
                let delta = active - lastActive
                if delta > 0 {
                    samples.append(
                        HKQuantitySample(
                            type: activeType,
                            quantity: HKQuantity(unit: kcal, doubleValue: delta),
                            start: row.timestamp,
                            end: row.timestamp
                        )
                    )
                }
                lastActive = active
            }
            if let basal = row.basalEnergyKilocalories {
                let delta = basal - lastBasal
                if delta > 0 {
                    samples.append(
                        HKQuantitySample(
                            type: basalType,
                            quantity: HKQuantity(unit: kcal, doubleValue: delta),
                            start: row.timestamp,
                            end: row.timestamp
                        )
                    )
                }
                lastBasal = basal
            }
        }
        try await addSamples(samples, builder: builder)
    }

    private static func addRideDistanceSamples(rides: [RideSegmentStats], builder: HKWorkoutBuilder) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: .distancePaddleSports) else { return }
        let samples: [HKQuantitySample] = rides.compactMap { ride in
            guard ride.distanceMeters > 0 else { return nil }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .meter(), doubleValue: ride.distanceMeters),
                start: ride.startedAt,
                end: ride.endedAt
            )
        }
        try await addSamples(samples, builder: builder)
    }

    private static func addRoundEncodings(
        style: Style,
        rounds: [RoundWindow],
        rides: [RideSegmentStats],
        config: HKWorkoutConfiguration,
        builder: HKWorkoutBuilder
    ) async throws {
        guard style != .samplesOnly else { return }
        for round in rounds {
            let activity = HKWorkoutActivity(
                workoutConfiguration: config,
                start: round.start,
                end: round.end,
                metadata: ["nl.dcsbl.rppl.detectionCode": round.code]
            )
            try await addWorkoutActivity(activity, builder: builder)
        }
        guard style == .ridePlusRest else { return }
        var events: [HKWorkoutEvent] = []
        for ride in rides {
            events.append(
                HKWorkoutEvent(
                    type: .motionResumed,
                    dateInterval: DateInterval(start: ride.startedAt, duration: 0),
                    metadata: nil
                )
            )
            events.append(
                HKWorkoutEvent(
                    type: .motionPaused,
                    dateInterval: DateInterval(start: ride.endedAt, duration: 0),
                    metadata: nil
                )
            )
        }
        try await addWorkoutEvents(events, builder: builder)
    }

    private static func addWorkoutActivity(_ activity: HKWorkoutActivity, builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.addWorkoutActivity(activity) { success, error in
                if let error {
                    continuation.resume(throwing: InjectError.saveFailed(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InjectError.saveFailed("addWorkoutActivity failed"))
                }
            }
        }
    }

    private static func saveRoute(
        locations: [LocationSample],
        workout: HKWorkout,
        healthStore: HKHealthStore
    ) async throws {
        let routePoints: [CLLocation] = locations.compactMap { sample in
            guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= 50 else { return nil }
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude),
                altitude: sample.altitude ?? 0,
                horizontalAccuracy: sample.horizontalAccuracy,
                verticalAccuracy: sample.verticalAccuracy ?? -1,
                course: sample.course ?? -1,
                speed: sample.speed ?? -1,
                timestamp: sample.timestamp
            )
        }
        guard !routePoints.isEmpty else { return }
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            routeBuilder.insertRouteData(routePoints) { success, error in
                if let error {
                    continuation.resume(throwing: InjectError.saveFailed(error.localizedDescription))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InjectError.saveFailed("insertRouteData failed"))
                }
            }
        }
        _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
    }
}
