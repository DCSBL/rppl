import Foundation
import Testing
@testable import RpplCore

@Suite("ActivityCodes")
struct ActivityCodesTests {
    @Test func pickerCodesAreOpaqueLowercase() {
        #expect(ActivityCodes.pickerCodes == [
            "wakeboard", "waterski", "monoski", "wakeskate", "kneeboard", "other",
        ])
        for code in ActivityCodes.pickerCodes {
            #expect(code == code.lowercased())
            #expect(ActivityCodes.localizedTitle(for: code) != code)
        }
    }

    @Test func missingCodeUsesFallbackTitleNotAsStorage() {
        // Compare within RpplCore's bundle: the test target's `.module` has no localizations,
        // so on a non-English simulator it would disagree with the library's localized title.
        let fallback = ActivityCodes.localizedTitle(for: nil)
        #expect(!fallback.isEmpty)
        #expect(ActivityCodes.localizedTitle(for: "") == fallback)
        #expect(!ActivityCodes.pickerCodes.map { ActivityCodes.localizedTitle(for: $0) }.contains(fallback))
    }

    @Test func unknownCodeDisplaysRawString() {
        #expect(ActivityCodes.localizedTitle(for: "foil") == "foil")
    }

    @Test func lastUsedStoresCodeNotTitle() {
        let suite = "activity-codes-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        ActivityCodes.rememberLastUsed(ActivityCodes.waterski, store: defaults)
        #expect(defaults.string(forKey: AppConstants.lastActivityCodeDefaultsKey) == "waterski")
        #expect(ActivityCodes.pickerLandingCode(store: defaults) == ActivityCodes.waterski)
        #expect(ActivityCodes.resolvedStartCode(store: defaults) == ActivityCodes.waterski)
        ActivityCodes.rememberLastUsed("foil", store: defaults)
        #expect(ActivityCodes.pickerLandingCode(store: defaults) == ActivityCodes.wakeboard)
        #expect(ActivityCodes.resolvedStartCode(store: defaults) == "foil")
    }

    @Test func manifestRoundTripKeepsOpaqueCode() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let original = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0",
            activityCode: ActivityCodes.wakeboard
        )
        let data = try encoder.encode(original)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"activityCode\":\"wakeboard\"") || json.contains("\"activityCode\" : \"wakeboard\""))
        #expect(!json.contains("Wakeboard"))
        let decoded = try decoder.decode(SessionManifest.self, from: data)
        #expect(decoded.activityCode == "wakeboard")
        #expect(decoded.activityCode != ActivityCodes.localizedTitle(for: decoded.activityCode))
    }
}
