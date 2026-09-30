#if PARK_ARRIVAL_NOTIFICATIONS
import CoreLocation
import RpplCore
import SwiftUI

/// Debug-tools-only screen for the park-arrival feature: the actual regions CoreLocation is
/// watching right now (not just what Rppl intended to monitor), whether notification permission
/// is actually working, and a per-park test-fire with a configurable delay.
struct ParkArrivalDebugView: View {
    @State private var controller = ParkArrivalController.shared
    @State private var store = ParkStore.shared
    @State private var delaySeconds: TimeInterval = 10
    @State private var testResults: [String: TestResult] = [:]
    @State private var notificationSummary = "Checking…"
    @State private var isSendingDiagnostic = false
    @State private var diagnosticResult: TestResult?

    private struct TestResult: Equatable {
        var message: String
        var isError: Bool
    }

    private static let delayOptions: [TimeInterval] = [5, 10, 30, 60]

    private var monitoredParks: [Park] {
        controller.monitoredParkIDs.compactMap { store.entry(id: $0)?.park }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Location", value: locationStatusText)
                LabeledContent("Notifications", value: notificationSummary)
                Button {
                    Task { await sendDiagnostic() }
                } label: {
                    if isSendingDiagnostic {
                        ProgressView()
                    } else {
                        Text("Send test notification now")
                    }
                }
                .disabled(isSendingDiagnostic)
                if let diagnosticResult {
                    Text(diagnosticResult.message)
                        .font(.caption)
                        .foregroundStyle(diagnosticResult.isError ? Color.red : Color.rpplMuted)
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Fires immediately, with no park or weather involved, to check the notification pipeline on its own.")
            }

            Section {
                Picker("Delay", selection: $delaySeconds) {
                    ForEach(Self.delayOptions, id: \.self) { seconds in
                        Text("\(Int(seconds))s").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Test delay")
            }

            Section {
                if monitoredParks.isEmpty {
                    Text("No parks currently monitored.")
                        .foregroundStyle(Color.rpplMuted)
                } else {
                    ForEach(monitoredParks) { park in
                        parkRow(park)
                    }
                }
            } header: {
                Text("Monitored parks (\(monitoredParks.count)/\(ParkArrivalPlanner.regionLimit))")
            } footer: {
                Text("Live list CoreLocation is actually watching right now, not just what Rppl intended to monitor.")
            }
        }
        .navigationTitle("Park Arrival Debug")
        .task { await refreshNotificationSummary() }
        .refreshable { await refreshNotificationSummary() }
    }

    private var locationStatusText: String {
        switch controller.authorizationStatus {
        case .notDetermined: String(localized: "Not determined")
        case .denied: String(localized: "Denied")
        case .restricted: String(localized: "Restricted")
        case .authorizedWhenInUse: String(localized: "When In Use")
        case .authorizedAlways: String(localized: "Always")
        @unknown default: String(localized: "Unknown")
        }
    }

    @ViewBuilder
    private func parkRow(_ park: Park) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(park.name)
                        .font(.body.weight(.semibold))
                    Text(
                        "\(park.location.lat, specifier: "%.5f"), \(park.location.lon, specifier: "%.5f") · \(Int(ParkArrivalPlanner.regionRadiusMeters))m radius"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.rpplMuted)
                }
                Spacer(minLength: 8)
                Button("Test") {
                    Task { await test(park) }
                }
                .buttonStyle(.bordered)
            }
            if let result = testResults[park.id] {
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(result.isError ? Color.red : Color.rpplMuted)
            }
        }
        .padding(.vertical, 2)
    }

    private func test(_ park: Park) async {
        testResults[park.id] = TestResult(message: String(localized: "Scheduling…"), isError: false)
        let outcome = await controller.sendTestArrivalNotification(parkID: park.id, delay: delaySeconds)
        switch outcome {
        case .success:
            testResults[park.id] = TestResult(
                message: String(localized: "Scheduled, fires in \(Int(delaySeconds))s."),
                isError: false
            )
        case .failure(let message):
            testResults[park.id] = TestResult(message: message, isError: true)
        }
    }

    private func sendDiagnostic() async {
        isSendingDiagnostic = true
        let outcome = await controller.sendImmediateDiagnosticNotification()
        switch outcome {
        case .success:
            diagnosticResult = TestResult(
                message: String(localized: "Sent. Check Notification Center or your lock screen now."),
                isError: false
            )
        case .failure(let message):
            diagnosticResult = TestResult(message: message, isError: true)
        }
        isSendingDiagnostic = false
        await refreshNotificationSummary()
    }

    private func refreshNotificationSummary() async {
        notificationSummary = await controller.notificationSettingsSummary()
    }
}

#Preview {
    NavigationStack {
        ParkArrivalDebugView()
    }
}
#endif
