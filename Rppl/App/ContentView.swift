import SwiftUI
import UIKit
import UniformTypeIdentifiers
import RpplCore

enum AppTab: Hashable {
    case logbook
    case parks
    case app
}

private enum AppTabIcons {
    /// Tab bar needs a ~25pt template image. Large SVG assets stretch across liquid glass.
    static let rppl = Image(uiImage: resizedTemplate(named: "icon-simple", pointSize: 25))

    private static func resizedTemplate(named name: String, pointSize: CGFloat) -> UIImage {
        let size = CGSize(width: pointSize, height: pointSize)
        let base = UIImage(named: name) ?? UIImage()
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.withRenderingMode(.alwaysTemplate)
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .logbook
    @State private var logbookNavigation = LogbookNavigationRequest()
    @State private var parksNavigation = ParksNavigationRequest()
    @State private var iCloud = PhoneICloudDriveController.shared
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var parkArrival = ParkArrivalController.shared
    @State private var showParkArrivalExplainer = false
    @State private var showICloudImport = false
    @State private var isManualICloudImport = false
    @State private var manualImportSummaries: [RemoteSessionSummary] = []
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var showImportError = false
    @State private var importErrorText: String?
    @State private var showAlreadyImportedAlert = false
    @State private var pendingDuplicateSessionId: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Logbook", systemImage: "book.fill", value: AppTab.logbook) {
                LogbookView(navigation: $logbookNavigation)
            }

            Tab("Parks", systemImage: "mappin.and.ellipse", value: AppTab.parks) {
                ParksView(navigation: $parksNavigation)
            }

            Tab(value: AppTab.app) {
                AppInfoView(
                    isImporting: isImporting,
                    onImportSessionTapped: presentManualImport
                )
            } label: {
                Label {
                    Text("Rppl")
                } icon: {
                    AppTabIcons.rppl
                }
            }
        }
        .tint(Color.rpplAccent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showICloudImport) {
            ICloudSessionImportView(
                summaries: isManualICloudImport
                    ? manualImportSummaries
                    : iCloud.pendingImportSummaries,
                iCloudImportEnabled: iCloud.isSyncEnabled && iCloud.isICloudAvailable,
                onImport: { ids in
                    showICloudImport = false
                    if isManualICloudImport {
                        isManualICloudImport = false
                    } else {
                        iCloud.dismissImportOffer()
                    }
                    Task {
                        await iCloud.importSelectedRemoteSessions(ids)
                    }
                },
                onCancel: {
                    showICloudImport = false
                    if isManualICloudImport {
                        isManualICloudImport = false
                    } else {
                        iCloud.dismissImportOffer()
                    }
                },
                onImportFromFile: {
                    showICloudImport = false
                    if isManualICloudImport {
                        isManualICloudImport = false
                    } else {
                        iCloud.dismissImportOffer()
                    }
                    showFileImporter = true
                }
            )
        }
        .onChange(of: iCloud.shouldOfferImport) { _, offer in
            if offer, !iCloud.suppressImportOffer {
                isManualICloudImport = false
                showICloudImport = true
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .alert(
            "Could not import session",
            isPresented: $showImportError,
            presenting: importErrorText
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .alert(
            "Already in logbook",
            isPresented: $showAlreadyImportedAlert
        ) {
            Button("Cancel", role: .cancel) {
                pendingDuplicateSessionId = nil
            }
            Button("Show") {
                if let sessionId = pendingDuplicateSessionId {
                    logbookNavigation.openSessionId = sessionId
                    logbookNavigation.highlightSessionId = sessionId
                    selectedTab = .logbook
                }
                pendingDuplicateSessionId = nil
            }
        } message: {
            Text("This session is already in your logbook.")
        }
        // `initial: true` covers a cold launch from the tap, where the arrival is set before this view appears.
        .onChange(of: parkArrival.pendingArrival, initial: true) { _, arrival in
            guard let arrival else { return }
            selectedTab = .parks
            parksNavigation.openParkId = arrival.parkID
            if arrival.isFirstTime {
                showParkArrivalExplainer = true
            }
            parkArrival.consumePendingArrival()
        }
        .sheet(isPresented: $showParkArrivalExplainer) {
            ParkArrivalExplainerView(onDismiss: { showParkArrivalExplainer = false })
        }
    }

    private func presentManualImport() {
        manualImportSummaries = iCloud.summariesForManualImport()
        isManualICloudImport = true
        showICloudImport = true
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            presentImportFailure(SessionExportImportError.detail(for: error))
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            Task {
                do {
                    let importedId = try await connectivity.importExportedSession(from: url)
                    isImporting = false
                    logbookNavigation.openSessionId = importedId
                    logbookNavigation.highlightSessionId = importedId
                    selectedTab = .logbook
                } catch let error as SessionExportImportError {
                    isImporting = false
                    switch error {
                    case .alreadyImported(let sessionId):
                        pendingDuplicateSessionId = sessionId
                        showAlreadyImportedAlert = true
                    case .unreadable(let message):
                        presentImportFailure(message)
                    }
                } catch {
                    isImporting = false
                    presentImportFailure(SessionExportImportError.detail(for: error))
                    WakeLog.error(.transfer, "export-file import: \(error.localizedDescription)")
                }
            }
        }
    }

    private func presentImportFailure(_ message: String) {
        importErrorText = message
        Task { @MainActor in
            showImportError = true
        }
    }
}

#Preview {
    ContentView()
}
