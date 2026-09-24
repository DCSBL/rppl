import MapKit
import RpplCore
import SwiftUI

struct ParkDetailView: View {
    let park: Park
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false

    var body: some View {
        List {
            Section {
                ParkMap(park: park, usesSatellite: usesSatellite)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                if let address = park.address {
                    Text(address)
                        .foregroundStyle(Color.rpplMuted)
                }
                Button {
                    ParkNavigation.openDirections(to: park)
                } label: {
                    Label("Navigate", systemImage: "location.fill")
                }
            }

            if let opening = park.opening {
                todaySection(opening)
                scheduleSection(opening)
            }

            ForEach(Array((park.cables ?? []).enumerated()), id: \.offset) { _, cable in
                cableSection(cable)
            }

            contactSection

            if let prices = park.prices, !prices.isEmpty {
                Section("Prices") {
                    ForEach(Array(prices.enumerated()), id: \.offset) { _, price in
                        LabeledContent {
                            Text(price.price)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(price.name)
                                if let note = price.note {
                                    Text(note).font(.caption).foregroundStyle(Color.rpplMuted)
                                }
                            }
                        }
                    }
                }
            }

            if let facilities = park.facilities, !facilities.isEmpty {
                Section("Facilities") {
                    Text(facilities.joined(separator: " · "))
                }
            }

            if let description = park.description, !description.isEmpty {
                Section("About") {
                    Text(description)
                }
            }

            if let links = park.links, !links.isEmpty {
                Section("Links") {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        if let url = URL(string: link.url) {
                            Link(link.kind.capitalized, destination: url)
                        }
                    }
                }
            }
        }
        .navigationTitle(park.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(isFavorite ? Text("Remove favorite") : Text("Add favorite"))
            }
        }
    }

    private func todaySection(_ opening: ParkOpening) -> some View {
        let day = park.schedule()
        return Section("Today") {
            if day.isOpen {
                ForEach(Array(day.windows.enumerated()), id: \.offset) { _, window in
                    LabeledContent {
                        Text(ParkFormatting.window(window))
                    } label: {
                        Text(window.label ?? String(localized: "Open"))
                    }
                    if let note = window.note {
                        Text(note).font(.caption).foregroundStyle(Color.rpplMuted)
                    }
                }
                if !day.availableSlots.isEmpty {
                    LabeledContent {
                        Text(day.availableSlots.map(\.id).joined(separator: ", "))
                    } label: {
                        Text("Blocks")
                    }
                }
                if opening.booking == "required" {
                    Text("Booking required")
                        .font(.caption)
                        .foregroundStyle(Color.rpplMuted)
                }
            } else {
                Text("Closed today")
                    .foregroundStyle(Color.rpplMuted)
            }
        }
    }

    @ViewBuilder
    private func scheduleSection(_ opening: ParkOpening) -> some View {
        if let rules = opening.rules, !rules.isEmpty {
            Section("Opening times") {
                ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                    LabeledContent {
                        Text("\(rule.open) – \(rule.close)")
                    } label: {
                        VStack(alignment: .leading) {
                            if let label = rule.label { Text(label) }
                            if let days = ParkFormatting.days(rule.days) {
                                Text(days).font(.caption).foregroundStyle(Color.rpplMuted)
                            }
                        }
                    }
                }
                if let note = opening.note {
                    Text(note).font(.caption).foregroundStyle(Color.rpplMuted)
                }
            }
        }
        if let slots = opening.slots, !slots.isEmpty {
            Section("Blocks") {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                    LabeledContent {
                        Text(ParkFormatting.slot(slot))
                    } label: {
                        Text(slot.label ?? slot.id)
                    }
                }
            }
        }
    }

    private func cableSection(_ cable: ParkCable) -> some View {
        Section(cable.name ?? String(localized: "Cable")) {
            if let direction = ParkFormatting.direction(cable.direction) {
                LabeledContent("Direction", value: direction)
            }
            if let length = cable.effectiveLengthM {
                LabeledContent("Length", value: DistanceFormat.meters(length))
            }
            if let description = cable.description {
                Text(description)
            }
        }
    }

    @ViewBuilder
    private var contactSection: some View {
        let phoneURL = park.phone.flatMap { phone in
            URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" })
        }
        let mailURL = park.email.flatMap { URL(string: "mailto:\($0)") }
        let webURL = park.website.flatMap { URL(string: $0) }
        if phoneURL != nil || mailURL != nil || webURL != nil {
            Section("Contact") {
                if let phone = park.phone, let phoneURL { Link(phone, destination: phoneURL) }
                if let email = park.email, let mailURL { Link(email, destination: mailURL) }
                if let website = park.website, let webURL { Link(website, destination: webURL) }
            }
        }
    }
}

private struct ParkMap: View {
    let park: Park
    let usesSatellite: Bool

    var body: some View {
        Map(initialPosition: .region(region)) {
            Marker(park.name, coordinate: coordinate(park.location.lat, park.location.lon))
                .tint(.red)
            ForEach(Array((park.cables ?? []).enumerated()), id: \.offset) { _, cable in
                let points = (cable.points ?? []).map { coordinate($0.lat, $0.lon) }
                if points.count >= 2 {
                    MapPolyline(coordinates: cable.direction?.isLoop == true ? points + [points[0]] : points)
                        .stroke(Color.rpplAccent, lineWidth: 3)
                }
            }
        }
        .mapStyle(usesSatellite ? .hybrid : .standard)
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
