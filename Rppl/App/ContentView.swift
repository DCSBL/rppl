import SwiftUI
import UIKit

enum AppTab: Hashable {
    case logbook
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
    @State private var iCloud = PhoneICloudDriveController.shared
    @State private var showICloudImport = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Logbook", systemImage: "book.fill", value: AppTab.logbook) {
                LogbookView(navigation: $logbookNavigation)
            }

            Tab(value: AppTab.app) {
                AppInfoView(
                    navigation: $logbookNavigation,
                    selectedTab: $selectedTab
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
                summaries: iCloud.pendingImportSummaries,
                onImport: { ids in
                    showICloudImport = false
                    iCloud.dismissImportReview()
                    Task {
                        await iCloud.importSelectedRemoteSessions(ids)
                    }
                },
                onCancel: {
                    iCloud.dismissImportOffer()
                    showICloudImport = false
                }
            )
        }
        .onChange(of: iCloud.showImportReviewAfterEnable) { _, show in
            if show {
                showICloudImport = true
            }
        }
        .onChange(of: iCloud.shouldOfferImport) { _, offer in
            if offer, !iCloud.suppressImportOffer {
                showICloudImport = true
            }
        }
    }
}

#Preview {
    ContentView()
}
