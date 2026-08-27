import SwiftUI
import UIKit

private enum AppTab: Hashable {
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

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Logbook", systemImage: "book.fill", value: AppTab.logbook) {
                LogbookView()
            }

            Tab(value: AppTab.app) {
                AppInfoView()
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
    }
}

#Preview {
    ContentView()
}
