import RpplCore
import SwiftUI
import WeatherKit

/// What Apple requires next to WeatherKit data: the Apple Weather mark and a link to the legal page.
struct WeatherAttributionInfo: Equatable, Sendable {
    var markLightURL: URL?
    var markDarkURL: URL?
    var legalURL: URL

    /// Apple's legal attribution page, for when the attribution could not be fetched.
    static let fallbackLegalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
    /// Plain "Apple Weather" text linking to the legal page.
    static let fallback = WeatherAttributionInfo(legalURL: fallbackLegalURL)
}

/// Attribution for screens that show stored WeatherKit values (a session's air weather), where no
/// weather request runs that would bring the attribution along. One attempt per app launch; the
/// fallback stays when it fails.
@Observable
@MainActor
final class WeatherAttributionProvider {
    static let shared = WeatherAttributionProvider()

    private(set) var info = WeatherAttributionInfo.fallback
    private var didAttempt = false

    func loadIfNeeded() async {
        guard !didAttempt else { return }
        didAttempt = true
        do {
            let attribution = try await WeatherService.shared.attribution
            info = WeatherAttributionInfo(
                markLightURL: attribution.combinedMarkLightURL,
                markDarkURL: attribution.combinedMarkDarkURL,
                legalURL: attribution.legalPageURL
            )
        } catch {
            WakeLog.debug(.ui, "weather attribution: \(error)")
        }
    }
}

/// Apple Weather mark plus a visible legal link. Show it wherever WeatherKit data is on screen.
struct AppleWeatherAttribution: View {
    @Environment(\.colorScheme) private var colorScheme
    let info: WeatherAttributionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Link(destination: info.legalURL) {
                if let mark = colorScheme == .dark ? info.markDarkURL : info.markLightURL {
                    AsyncImage(url: mark) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Text("Apple Weather")
                    }
                    .frame(height: 14)
                } else {
                    Text("Apple Weather")
                }
            }
            .accessibilityLabel(Text("Apple Weather"))
            Link("Weather data sources", destination: info.legalURL)
                .underline()
        }
        .font(.caption2)
        .foregroundStyle(Color.rpplMuted)
    }
}
