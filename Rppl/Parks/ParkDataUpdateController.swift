import Observation
import RpplCore
import SwiftUI
import WidgetKit

/// Downloads park data updates (see `ParkDataUpdater`) and keeps what the Parks UI shows about it:
/// spinner state, the 5 second error, haptic triggers and the "checked … · data from …" line.
@Observable
@MainActor
final class ParkDataUpdateController {
    static let shared = ParkDataUpdateController()

    private(set) var isRefreshing = false
    /// Shown at the spinner for `errorDisplayDuration`, then cleared.
    private(set) var errorMessage: String?
    private(set) var startedCount = 0
    private(set) var successCount = 0
    private(set) var failureCount = 0
    private(set) var state: ParkDataUpdateState
    private(set) var pointer: ParkDataStore.Pointer?

    var fetcher: ParkDataFetching = GitHubParkDataFetcher()
    private var errorTask: Task<Void, Never>?

    init() {
        state = Self.loadState()
        pointer = ParkDataStore.app.pointer()
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: AppSettingsKey.parkDataUpdatesEnabled) }

    /// When the installed data was published (the manifest's `publishedAt`).
    var dataPublishedAt: Date? {
        pointer.flatMap { ISO8601DateFormatter().date(from: $0.publishedAt) }
    }

    /// Pull to refresh or the Settings row. Faked (nothing downloaded) right after a real success.
    func manualRefresh() async {
        guard isEnabled, !isRefreshing else { return }
        await run(manual: true)
    }

    /// In-app daily check, for riders without a park widget (no background refresh).
    func refreshIfDue() async {
        guard isEnabled, !isRefreshing,
              ParkDataRefreshPolicy.isDailyCheckDue(state: state, now: Date()) else { return }
        await run(manual: false)
    }

    /// Fixed per installation, so riders spread over the 24 hours instead of all asking at once.
    func dailyOffsetFraction() -> Double {
        if let fraction = state.dailyOffsetFraction { return fraction }
        let fraction = Double.random(in: 0..<1)
        state.dailyOffsetFraction = fraction
        saveState()
        return fraction
    }

    /// Background refresh: only when updates are on and the last success is old enough.
    func backgroundRefresh() async -> Bool {
        guard isEnabled, !isRefreshing,
              ParkDataRefreshPolicy.isDailyCheckDue(
                  state: state, now: Date(), minimumAge: ParkDataRefreshPolicy.backgroundMinimumAge
              ) else { return true }
        await run(manual: false)
        return state.lastRealAttemptSucceeded
    }

    private func run(manual: Bool) async {
        isRefreshing = true
        clearError()
        defer { isRefreshing = false }
        if manual { startedCount += 1 }

        let started = Date()
        if manual, ParkDataRefreshPolicy.shouldFakeManualRefresh(state: state, now: started) {
            try? await Task.sleep(for: .seconds(Double.random(in: ParkDataRefreshPolicy.fakeDurationRange)))
            state.lastAttempt = Date()
            state.lastAttemptWasFake = true
            saveState()
            successCount += 1
            return
        }

        let result: Result<ParkDataUpdateOutcome, Error>
        do {
            result = .success(try await ParkDataUpdater(store: .app).update(using: fetcher))
        } catch {
            result = .failure(error)
        }
        if manual {
            let remaining = ParkDataRefreshPolicy.minimumRefreshDuration - Date().timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
        }

        let now = Date()
        state.lastAttempt = now
        state.lastAttemptWasFake = false
        switch result {
        case .success(let outcome):
            state.lastRealAttemptSucceeded = true
            state.lastSuccess = now
            state.lastError = nil
            if outcome == .appUpdateRequired {
                showError(String(localized: "Update the app to get new park data"))
            } else if manual {
                successCount += 1
            }
            pointer = ParkDataStore.app.pointer()
            ParkStore.shared.reload()
            WidgetCenter.shared.reloadAllTimelines()
        case .failure(let error):
            state.lastRealAttemptSucceeded = false
            state.lastError = "\(error)"
            WakeLog.error(.store, "park data update: \(error)")
            if manual { failureCount += 1 }
            showError(String(localized: "Couldn’t update park data"))
        }
        saveState()
    }

    /// "Checked 21 hours ago · Data from 22 Oct 2026 at 12:41", or nil while updates are off.
    func statusLine(now: Date = Date()) -> String? {
        guard isEnabled else { return nil }
        var parts: [String] = []
        if let last = state.lastAttempt {
            parts.append(String(localized: "Checked \(Self.ageText(since: last, now: now))"))
            if !state.lastAttemptWasFake, !state.lastRealAttemptSucceeded {
                parts.append(String(localized: "last attempt failed"))
            }
        } else {
            parts.append(String(localized: "Not checked yet"))
        }
        if let published = dataPublishedAt {
            parts.append(String(localized: "Data from \(published.formatted(date: .abbreviated, time: .shortened))"))
        }
        return parts.joined(separator: " · ")
    }

    static func ageText(since date: Date, now: Date) -> String {
        if ParkDataAge(from: date, to: now) == .lessThanMinute {
            return String(localized: "less than a minute ago")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private func showError(_ message: String) {
        errorTask?.cancel()
        withRpplAnimation { errorMessage = message }
        errorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ParkDataRefreshPolicy.errorDisplayDuration))
            guard !Task.isCancelled else { return }
            self?.clearError()
        }
    }

    private func clearError() {
        errorTask?.cancel()
        if errorMessage != nil { withRpplAnimation { errorMessage = nil } }
    }

    private static func loadState() -> ParkDataUpdateState {
        guard let data = UserDefaults.standard.data(forKey: AppSettingsKey.parkDataUpdateState),
              let state = try? JSONDecoder().decode(ParkDataUpdateState.self, from: data) else {
            return ParkDataUpdateState()
        }
        return state
    }

    private func saveState() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: AppSettingsKey.parkDataUpdateState)
        }
    }
}

/// The "checked … · data from …" line under the parks list and in Info. Re-evaluates every 30 s so
/// the relative time keeps up.
struct ParkDataStatusLine: View {
    let controller: ParkDataUpdateController
    var alignment: TextAlignment = .center

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let text = controller.statusLine(now: context.date) {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Color.rpplMuted)
                    .multilineTextAlignment(alignment)
                    .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
                    .accessibilityLabel(text)
            }
        }
    }
}

/// Error shown for a few seconds at the pull-to-refresh spinner.
struct ParkDataErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.rpplText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Shown under the Parks header while pulling down and while fetching: a ring that fills with the
/// pull, a spinner while updating, and the "checked … · data from …" line.
struct ParkDataPullIndicator: View {
    let controller: ParkDataUpdateController
    /// 0...1 of the pull distance needed to trigger a refresh.
    let progress: Double

    var body: some View {
        VStack(spacing: 6) {
            if controller.isRefreshing {
                ProgressView()
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.rpplAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20, height: 20)
            }
            if controller.isRefreshing {
                Text("Updating park data…")
                    .font(.footnote)
                    .foregroundStyle(Color.rpplMuted)
            } else {
                ParkDataStatusLine(controller: controller)
            }
        }
        .opacity(controller.isRefreshing ? 1 : progress)
        .accessibilityElement(children: .combine)
    }
}
