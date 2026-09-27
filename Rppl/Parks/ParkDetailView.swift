import MapKit
import RpplCore
import SwiftUI

struct ParkDetailView: View {
    let park: Park
    let entry: ParkEntry?
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var weatherProvider = ParksWeatherProvider.shared
    @State private var weather: ParkWeather?
    @State private var waterTemperatureProvider = ParkWaterTemperatureProvider.shared
    @State private var waterTemperature: ParkWaterTemperature?
    @AppStorage(AppSettingsKey.parkWaterTemperatureEnabled) private var waterTemperatureEnabled = false
    @AppStorage(AppSettingsKey.didDeclineParkWaterTemperaturePrompt) private var didDeclineWaterTemperaturePrompt = false
    @State private var showWaterTemperaturePrompt = false
    @AppStorage(AppSettingsKey.parkEditorEnabled) private var editorEnabled = true
    @State private var showEditor = false
    @State private var showMail = false
    @State private var confirmRemove = false

    private var bookingURL: URL? {
        park.links?.first { $0.kind.lowercased() == "booking" }.flatMap { URL(string: $0.url) }
    }

    /// Section-level "these sections are changed" summary against the bundled version; empty for a brand-new custom park.
    private var changedSections: [ParkSection] {
        guard let base = entry?.bundledPark else { return [] }
        return ParkDiff.changedSections(from: base, to: park)
    }

    /// The park has a configured source but the (global) feature is off and the user hasn't already
    /// dismissed the inline offer — so there's something to invite them to turn on.
    private var showsWaterTemperaturePromptRow: Bool {
        park.waterTemperature != nil && !waterTemperatureEnabled && !didDeclineWaterTemperaturePrompt
    }

    var body: some View {
        let daySchedule = park.opening != nil ? park.schedule() : nil
        ScrollView {
            VStack(spacing: 12) {
                updateCard
                mapCard
                if let daySchedule {
                    todayCard(daySchedule)
                    openingTimesCard
                    blocksCard(daySchedule)
                }
                ForEach(Array((park.cables ?? []).enumerated()), id: \.offset) { _, cable in
                    cableCard(cable)
                }
                contactCard
                pricesCard
                aboutCard
                linksCard
                footer
            }
            .padding(.horizontal, LogbookLayout.horizontalInset)
            .padding(.vertical, 8)
        }
        .background(RpplBackdrop())
        .navigationTitle(park.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(isFavorite ? Text("Remove favorite") : Text("Add favorite"))
            }
            if editorEnabled {
                ToolbarItem(placement: .primaryAction) { editMenu }
            }
        }
        .sheet(isPresented: $showEditor) {
            ParkEditorView(original: park, onSaved: {})
        }
        .sheet(isPresented: $showMail) {
            ParkMailComposer(park: park, changedSections: changedSections) { showMail = false }
                .ignoresSafeArea()
        }
        .confirmationDialog(removeTitle, isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(removeTitle, role: .destructive) { ParkStore.shared.removeUserVersion(id: park.id) }
        }
        .task {
            async let weatherResult = weatherProvider.weather(for: park)
            async let waterTemperatureResult = waterTemperatureProvider.temperature(for: park)
            weather = await weatherResult
            waterTemperature = await waterTemperatureResult
        }
        .onChange(of: waterTemperatureEnabled) { _, isEnabled in
            guard isEnabled else { return }
            Task { waterTemperature = await waterTemperatureProvider.temperature(for: park) }
        }
        .alert(
            String(localized: "Show water temperature?"),
            isPresented: $showWaterTemperaturePrompt
        ) {
            Button(String(localized: "Not now"), role: .cancel) {
                didDeclineWaterTemperaturePrompt = true
            }
            Button(String(localized: "OK")) {
                waterTemperatureEnabled = true
            }
        } message: {
            Text(
                "Rppl fetches this from an external, official service (Rijkswaterstaat). The reading is an estimate. You can change this later in Settings."
            )
        }
    }

    // MARK: Editing

    private var removeTitle: String {
        entry?.origin == .custom ? String(localized: "Delete park") : String(localized: "Revert to app version")
    }

    private var editMenu: some View {
        Menu {
            Button("Edit", systemImage: "pencil") { showEditor = true }
            Button("Share", systemImage: "square.and.arrow.up") { ParkShare.share(park) }
            if let origin = entry?.origin, origin != .bundled {
                Button("Send to Rppl", systemImage: "envelope") {
                    if MailAvailability.canSend {
                        showMail = true
                    } else if let url = ParkShare.mailtoURL(for: park, changedSections: changedSections) {
                        openURL(url)
                    } else {
                        ParkShare.share(park)
                    }
                }
                Button(removeTitle, systemImage: "arrow.uturn.backward", role: .destructive) { confirmRemove = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("Edit park"))
    }

    @ViewBuilder
    private var updateCard: some View {
        if let entry, entry.hasNewerBundled {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Update available")
                Text("This park was updated in the app since you edited it. Keep your version or switch to the app version?")
                    .font(.subheadline)
                    .foregroundStyle(Color.rpplMuted)
                HStack {
                    Button("Keep my version") { ParkStore.shared.keepMine(entry) }
                        .buttonStyle(.bordered)
                    Button("Use app version") { ParkStore.shared.removeUserVersion(id: entry.id) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .logbookCardChrome()
        }
    }

    // MARK: Cards

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ParkMap(park: park, usesSatellite: usesSatellite, weather: weather)
                .frame(height: 220)
                .logbookNestedClip()

            if let address = park.address {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(Color.rpplMuted)
            }

            Button {
                ParkNavigation.openDirections(to: park)
            } label: {
                Label("Navigate", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let bookingURL {
                Link(destination: bookingURL) {
                    Label("Book online", systemImage: "ticket")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .logbookCardChrome()
    }

    private func todayCard(_ day: ParkDaySchedule) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Today")

            if !day.isScheduleKnown {
                Text("Opening hours unknown")
                    .font(.title3.bold())
                    .foregroundStyle(Color.rpplMuted)
            } else if day.isOpen {
                ForEach(Array(day.windows.enumerated()), id: \.offset) { _, window in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ParkFormatting.openFromTo(window))
                            .font(.title3.bold())
                            .foregroundStyle(Color.rpplText)
                        if let detail = windowDetail(window) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(Color.rpplMuted)
                        }
                    }
                }
                if !day.availableSlots.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Blocks")
                            .font(.caption)
                            .foregroundStyle(Color.rpplMuted)
                        FlowLayout {
                            ForEach(day.availableSlots, id: \.id) { slot in
                                ParkChip(
                                    text: ParkFormatting.slot(slot),
                                    tint: Color.rpplAccent,
                                    fill: Color.rpplAccent.opacity(0.14)
                                )
                            }
                        }
                    }
                }
            } else {
                Text("Closed today")
                    .font(.title3.bold())
                    .foregroundStyle(.red)
            }

            if weather != nil || waterTemperature != nil || showsWaterTemperaturePromptRow {
                Divider().overlay(Color.rpplFill)
                conditionsSection(weather: weather, waterTemperature: waterTemperature)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .logbookCardChrome()
    }

    private var waterTemperaturePromptRow: some View {
        Button {
            showWaterTemperaturePrompt = true
        } label: {
            Label(String(localized: "Show water temperature"), systemImage: "water.waves")
                .font(.subheadline)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.rpplAccent)
    }

    private func conditionsSection(weather: ParkWeather?, waterTemperature: ParkWaterTemperature?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 16) {
                if let weather {
                    Label(TemperatureFormat.celsius(weather.temperatureCelsius), systemImage: "thermometer.medium")
                    Label(windSummary(weather), systemImage: "wind")
                    Label(weather.rainForecast.label, systemImage: "cloud.rain")
                    if weather.isHighUV {
                        Label(String(localized: "High UV"), systemImage: "sun.max.trianglebadge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                }
                if let waterTemperature {
                    Label(TemperatureFormat.celsius(waterTemperature.celsius), systemImage: "water.waves")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.rpplText)

            if waterTemperature == nil, showsWaterTemperaturePromptRow {
                waterTemperaturePromptRow
            }

            if let waterTemperature {
                Text(String(localized: "Estimate near \(waterTemperature.stationName), via \(waterTemperature.providerName)"))
                    .font(.caption2)
                    .foregroundStyle(Color.rpplMuted)
            }

            if let weather, let legal = weather.legalURL {
                Link(destination: legal) {
                    HStack(spacing: 4) {
                        if let mark = colorScheme == .dark ? weather.markDarkURL : weather.markLightURL {
                            AsyncImage(url: mark) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Text("Apple Weather")
                            }
                            .frame(height: 12)
                        } else {
                            Text("Apple Weather")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.rpplMuted)
                }
            }
        }
    }

    private func windSummary(_ weather: ParkWeather) -> String {
        let direction = CompassDirection8(degrees: weather.windDirectionDegrees)
        let speed = DistanceFormat.kilometersPerHour(weather.windKmh)
        let beaufort = BeaufortScale.label(forKmh: weather.windKmh)
        return "\(direction.name) · \(speed) · \(beaufort)"
    }

    private var openingTimesCard: some View {
        let months = ParkSchedule.months(for: park.opening)
        let current = ParkFormatting.currentMonth(in: park)
        return Group {
            if !months.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Opening times")
                    ForEach(months) { entry in
                        monthTile(entry, isCurrent: entry.month == current)
                    }
                    if let note = park.opening?.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Color.rpplMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .logbookCardChrome()
            }
        }
    }

    private func monthTile(_ entry: ParkMonthSchedule, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ParkFormatting.monthName(entry.month))
                .font(.subheadline.bold())
                .foregroundStyle(isCurrent ? Color.rpplAccent : Color.rpplText)
            ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(lineTitle(line))
                            .foregroundStyle(Color.rpplText)
                        Spacer(minLength: 8)
                        Text("\(line.open) – \(line.close)")
                            .monospacedDigit()
                            .foregroundStyle(Color.rpplText)
                    }
                    .font(.subheadline)
                    if let note = line.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Color.rpplMuted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .parkHighlightBackground(isCurrent, opacity: 0.14)
    }

    private func blocksCard(_ day: ParkDaySchedule) -> some View {
        let slots = park.opening?.slots ?? []
        let todayIds = Set(day.availableSlots.map(\.id))
        return Group {
            if !slots.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Blocks")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(slots, id: \.id) { slot in
                            blockTile(slot, highlighted: todayIds.contains(slot.id))
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if let durations = ParkFormatting.bookingDurations(park.opening?.bookingMinutes) {
                            Text("Bookable for \(durations)")
                        }
                        if !todayIds.isEmpty {
                            Text("Highlighted blocks are available today")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.rpplMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .logbookCardChrome()
            }
        }
    }

    private func blockTile(_ slot: ParkSlot, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ParkFormatting.slot(slot))
                .font(.subheadline.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(highlighted ? Color.rpplAccent : Color.rpplText)
            if let label = slotLabel(slot) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.rpplMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .parkHighlightBackground(highlighted, opacity: 0.24)
    }

    private func cableCard(_ cable: ParkCable) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cable.name ?? String(localized: "Cable")).font(.headline).foregroundStyle(Color.rpplText)
            FlowLayout {
                if let type = ParkFormatting.cableType(cable.direction) {
                    ParkChip(
                        text: type,
                        systemImage: cable.direction?.isLoop == true
                            ? "arrow.triangle.2.circlepath" : "arrow.left.and.right"
                    )
                }
                if let direction = ParkFormatting.loopDirection(cable.direction) {
                    ParkChip(
                        text: direction,
                        systemImage: cable.direction == .clockwise ? "arrow.clockwise" : "arrow.counterclockwise"
                    )
                }
                if let length = cable.effectiveLengthM {
                    ParkChip(text: DistanceFormat.meters(length), systemImage: "ruler")
                }
            }
            if let description = cable.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Color.rpplText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .logbookCardChrome()
    }

    @ViewBuilder
    private var contactCard: some View {
        let phoneURL = park.phone.flatMap { URL(string: "tel:" + $0.filter { $0.isNumber || $0 == "+" }) }
        let mailURL = park.email.flatMap { URL(string: "mailto:\($0)") }
        let webURL = park.website.flatMap { URL(string: $0) }
        if phoneURL != nil || mailURL != nil || webURL != nil {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Contact")
                if let phone = park.phone, let phoneURL {
                    Link(destination: phoneURL) { contactRow(phone, systemImage: "phone") }
                }
                if let email = park.email, let mailURL {
                    Link(destination: mailURL) { contactRow(email, systemImage: "envelope") }
                }
                if let website = park.website, let webURL {
                    Link(destination: webURL) { contactRow(website, systemImage: "safari") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .logbookCardChrome()
        }
    }

    @ViewBuilder
    private var pricesCard: some View {
        if let prices = park.prices, !prices.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Prices")
                ForEach(Array(prices.enumerated()), id: \.offset) { _, price in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(price.name).foregroundStyle(Color.rpplText)
                            if let note = price.note {
                                Text(note).font(.caption).foregroundStyle(Color.rpplMuted)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(price.price).bold().foregroundStyle(Color.rpplText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .logbookCardChrome()
        }
    }

    @ViewBuilder
    private var aboutCard: some View {
        let facilities = park.facilities ?? []
        let description = park.description ?? ""
        if !facilities.isEmpty || !description.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if !description.isEmpty {
                    sectionTitle("About")
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Color.rpplText)
                }
                if !facilities.isEmpty {
                    sectionTitle("Facilities")
                    FlowLayout {
                        ForEach(facilities, id: \.self) { ParkChip(text: $0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .logbookCardChrome()
        }
    }

    @ViewBuilder
    private var linksCard: some View {
        let links = (park.links ?? []).filter { $0.kind.lowercased() != "booking" }
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Links")
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    if let url = URL(string: link.url) {
                        Link(destination: url) {
                            Label(link.kind.capitalized, systemImage: "link")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .logbookCardChrome()
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if park.opening != nil {
                Text("Opening times may change and can be outdated. Verify with the park before booking.")
            }
            if let author = park.author, author.caseInsensitiveCompare("rppl") != .orderedSame {
                Text("Credits: \(author)")
            }
            if let badge = ParkOriginBadge.text(for: entry) {
                Text(badge)
            }
            if let updated = park.lastUpdated {
                Text("Last updated: \(updated.formatted(date: .long, time: .omitted))")
            }
        }
        .font(.caption)
        .foregroundStyle(Color.rpplMuted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: Helpers

    private func contactRow(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24, alignment: .center)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .textCase(.uppercase)
            .font(.caption.weight(.semibold))
            .foregroundStyle(RpplDesign.headerColor)
            .accessibilityLabel(Text(key))
            .accessibilityAddTraits(.isHeader)
    }

    private func slotLabel(_ slot: ParkSlot) -> String? {
        if let label = slot.label { return label }
        return park.opening?.numbered == false ? nil : String(localized: "Block \(slot.id)")
    }

    private func windowDetail(_ window: ParkTimeWindow) -> String? {
        let parts = [window.label.flatMap { ParkFormatting.isMonthLabel($0) ? nil : $0 }, window.note]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    private func lineTitle(_ line: ParkScheduleLine) -> String {
        var parts = [ParkFormatting.days(line.days) ?? String(localized: "Daily")]
        if let label = line.label, !ParkFormatting.isMonthLabel(label) { parts.append(label) }
        if let from = line.from { parts.append(String(localized: "from \(from)")) }
        if let until = line.until { parts.append(String(localized: "until \(until)")) }
        if let dates = line.dates { parts.append(dates.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

private struct ParkMap: View {
    let park: Park
    let usesSatellite: Bool
    let weather: ParkWeather?

    @State private var mapHeading: Double = 0

    var body: some View {
        Map(initialPosition: .region(region)) {
            Marker(park.name, coordinate: coordinate(park.location.lat, park.location.lon))
                .tint(.red)
            ForEach(startMarkers, id: \.id) { marker in
                Annotation("", coordinate: marker.coordinate, anchor: .center) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.rpplAccent, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .rotationEffect(.degrees((marker.bearing ?? 0) - mapHeading))
                        .accessibilityLabel(Text("Start"))
                }
            }
            ForEach(Array((park.cables ?? []).enumerated()), id: \.offset) { _, cable in
                let points = (cable.points ?? []).map { coordinate($0.lat, $0.lon) }
                if points.count >= 2 {
                    MapPolyline(coordinates: cable.direction?.isLoop == true ? points + [points[0]] : points)
                        .stroke(Color.rpplAccent, lineWidth: 3)
                }
            }
        }
        .mapStyle(usesSatellite ? .hybrid : .standard)
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
        }
        .overlay(alignment: .topTrailing) {
            if let weather {
                WindRoseView(
                    directionDegrees: weather.windDirectionDegrees,
                    speedKmh: weather.windKmh,
                    mapHeading: mapHeading
                )
                .padding(10)
            }
        }
    }

    private struct StartMarker {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let bearing: Double?
    }

    private var startMarkers: [StartMarker] {
        (park.cables ?? []).enumerated().flatMap { cableIndex, cable in
            cable.starts.enumerated().map { startIndex, start in
                StartMarker(
                    id: "\(cableIndex)-\(startIndex)",
                    coordinate: coordinate(start.point.lat, start.point.lon),
                    bearing: start.bearingDegrees
                )
            }
        }
    }

    private var region: MKCoordinateRegion {
        let all = [park.location]
            + (park.cables ?? []).flatMap { ($0.points ?? []).map(\.coordinate) }
        let lats = all.map(\.lat)
        let lons = all.map(\.lon)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.004),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 0.004)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private func coordinate(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

private extension View {
    /// Accent tint layered over the normal nested fill, so highlights stay lighter than the card in dark mode.
    func parkHighlightBackground(_ highlighted: Bool, opacity: Double) -> some View {
        logbookNestedBackground(highlighted ? Color.rpplAccent.opacity(opacity) : Color.clear)
            .logbookNestedBackground(Color.rpplFill)
    }
}
