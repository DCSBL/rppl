import CoreLocation
import MapKit
import RpplCore
import SwiftUI

/// Short explanation at the top of a page, shown while walking through a new park.
struct ParkPageIntro: View {
    let page: ParkEditorPage
    let text: LocalizedStringKey
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        if session.isGuided {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: page.systemImage)
                        .font(.title2)
                        .foregroundStyle(Color.rpplAccent)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }
        }
    }
}

// MARK: - Basics

struct ParkBasicsPage: View {
    @Environment(ParkEditorSession.self) private var session
    @State private var location = ParksLocationProvider()
    @State private var pickingLocation = false
    @State private var wantsCurrentLocation = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        @Bindable var session = session
        Form {
            ParkPageIntro(
                page: .basics,
                text: "Start with the name and where the park is. Move the map to the dock and set the pin. Everything else on this page is optional."
            )
            Section {
                ParkTextInput(title: "Park name", text: $session.park.name, field: .name)
                    .textInputAutocapitalization(.words)
                    .focused($nameFocused)
            } header: {
                Text("Name")
            } footer: {
                ParkFieldHelp(
                    text: "Required. The name the park goes by, as on its own website.",
                    counter: (session.park.name.count, ParkTextField.name.maxLength)
                )
            }

            locationSection

            Section {
                ParkTextInput(
                    title: "Street, postcode, city",
                    text: $session.park.address.orEmpty,
                    field: .address,
                    axis: .vertical,
                    lines: 1...3
                )
                .textContentType(.fullStreetAddress)
            } header: {
                Text("Address")
            } footer: {
                ParkFieldHelp(
                    text: "Shown under the map. Optional.",
                    counter: (session.park.address?.count ?? 0, ParkTextField.address.maxLength)
                )
            }

            Section {
                NavigationLink {
                    ParkTimeZonePage(
                        selection: Binding(
                            get: { session.park.resolvedTimeZone.identifier },
                            set: {
                                session.park.timezone = $0
                                session.timeZoneIsManual = true
                            }
                        ),
                        suggestion: ParkPlaceResolver.shared.timeZone(near: session.park.location)
                    )
                } label: {
                    LabeledContent("Time zone", value: session.park.resolvedTimeZone.identifier)
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Set from the location. It decides what \"today\" means at the park and when it opens.")
            }
        }
        .navigationTitle("Basics")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickingLocation) {
            LocationPickerView(
                coordinate: $session.park.location,
                userLocation: location.coordinate
            )
        }
        .task { location.refresh() }
        .onChange(of: location.coordinate) { _, fix in
            guard wantsCurrentLocation, let fix else { return }
            wantsCurrentLocation = false
            session.park.location = fix
        }
        .onChange(of: session.park.location) { _, new in
            guard ParkDraft.isValid(new), !session.timeZoneIsManual else { return }
            Task {
                if let zone = await ParkPlaceResolver.shared.resolveTimeZone(at: new), !session.timeZoneIsManual {
                    session.park.timezone = zone.identifier
                }
            }
        }
        .onAppear {
            if session.isGuided, session.park.name.isEmpty { nameFocused = true }
        }
    }

    private var locationSection: some View {
        let hasLocation = ParkDraft.isValid(session.park.location)
        return Section {
            if hasLocation {
                ParkMiniMap(coordinate: session.park.location)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                LabeledContent("Latitude") { coordinateText(session.park.location.lat) }
                LabeledContent("Longitude") { coordinateText(session.park.location.lon) }
            } else {
                Label("No location yet", systemImage: "mappin.slash")
                    .foregroundStyle(.secondary)
            }
            Button(hasLocation ? "Move the pin on the map" : "Set location on the map", systemImage: "scope") {
                pickingLocation = true
            }
            Button("Use my current location", systemImage: "location") {
                if let here = location.coordinate {
                    session.park.location = here
                } else {
                    wantsCurrentLocation = true
                    location.requestAccess()
                }
            }
            if location.availability == .denied {
                Label("Location access is off for Rppl. Set the pin on the map instead.", systemImage: "location.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Location")
        } footer: {
            Text("Required. Put the pin on the dock: riders get directions to it. The coordinates follow the pin.")
        }
    }

    private func coordinateText(_ value: Double) -> some View {
        Text(value.formatted(.number.precision(.fractionLength(6)).locale(Locale(identifier: "en_US_POSIX"))))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

/// Searchable list of time zones, the one resolved from the location on top.
private struct ParkTimeZonePage: View {
    @Binding var selection: String
    let suggestion: TimeZone?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var identifiers: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return all }
        return all.filter { $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        List {
            if query.isEmpty, let suggestion {
                Section("Suggested for this location") { row(suggestion.identifier) }
            }
            Section { ForEach(identifiers, id: \.self, content: row) }
        }
        .navigationTitle("Time zone")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query)
    }

    private func row(_ identifier: String) -> some View {
        Button {
            selection = identifier
            dismiss()
        } label: {
            HStack {
                Text(identifier.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.primary)
                Spacer()
                if identifier == selection { Image(systemName: "checkmark").foregroundStyle(Color.rpplAccent) }
            }
        }
    }
}

// MARK: - Contact

struct ParkContactPage: View {
    @Environment(ParkEditorSession.self) private var session
    @FocusState private var focused: Field?

    private enum Field { case phone, email, website }

    var body: some View {
        @Bindable var session = session
        let park = session.park
        Form {
            ParkPageIntro(
                page: .contact,
                text: "How can riders reach the park, and where do they find it online? Fill in what you know and leave out the rest."
            )
            Section {
                TextField("Phone", text: phoneBinding, prompt: Text(verbatim: "+31 10 260 0110"))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($focused, equals: .phone)
            } header: {
                Text("Phone")
            } footer: {
                ParkFieldHelp(
                    text: "The number riders can call about bookings and opening times. Include the country code when you can.",
                    problem: focused == .phone ? nil : phoneProblem(park.phone)
                )
            }
            Section {
                TextField("Email", text: emailBinding, prompt: Text(verbatim: "info@park.nl"))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
            } header: {
                Text("Email")
            } footer: {
                ParkFieldHelp(
                    text: "Where riders can send questions.",
                    problem: focused == .email ? nil : emailProblem(park.email)
                )
            }
            Section {
                TextField("Website", text: websiteBinding, prompt: Text(verbatim: "www.park.nl"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .website)
            } header: {
                Text("Website")
            } footer: {
                ParkFieldHelp(
                    text: "The park's own website. Booking, Instagram and other pages go under Links.",
                    problem: focused == .website ? nil : websiteProblem(park.website)
                )
            }
            ParkLinksSection()
        }
        .navigationTitle("Contact and links")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focused) { old, _ in
            // Leaving the website field completes "park.nl" to "https://park.nl".
            if old == .website, let site = session.park.website, let full = ParkText.normalizedWebAddress(site), full != site {
                session.park.website = full
            }
        }
    }

    private func cleaned(_ binding: Binding<String?>, field: ParkTextField) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { new in
                let clean = ParkText.sanitizeTyping(new, field: field)
                binding.wrappedValue = clean.isEmpty ? nil : clean
            }
        )
    }

    private var phoneBinding: Binding<String> { cleaned(Bindable(session).park.phone, field: .phone) }
    private var emailBinding: Binding<String> { cleaned(Bindable(session).park.email, field: .email) }
    private var websiteBinding: Binding<String> { cleaned(Bindable(session).park.website, field: .url) }

    private func phoneProblem(_ phone: String?) -> LocalizedStringKey? {
        guard let phone, let issue = ParkText.phoneIssue(phone) else { return nil }
        switch issue {
        case .tooFewDigits: return "That looks too short for a phone number."
        case .tooManyDigits: return "That looks too long for a phone number."
        default: return "Use digits, spaces and + ( ) - . only."
        }
    }

    private func emailProblem(_ email: String?) -> LocalizedStringKey? {
        guard let email, ParkText.emailIssue(email) != nil else { return nil }
        return "That does not look like an email address yet. It should look like name@park.nl."
    }

    private func websiteProblem(_ website: String?) -> LocalizedStringKey? {
        guard let website, !website.isEmpty, ParkText.normalizedWebAddress(website) == nil else { return nil }
        return "That does not look like a web address yet. Try park.nl or https://park.nl."
    }
}

// MARK: - About

struct ParkAboutPage: View {
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        @Bindable var session = session
        Form {
            ParkPageIntro(
                page: .about,
                text: "A few words about the park and what is on site. Both are optional."
            )
            Section {
                ParkTextInput(
                    title: "What kind of park is it?",
                    text: $session.park.description.orEmpty,
                    field: .description,
                    axis: .vertical,
                    lines: 4...12
                )
            } header: {
                Text("About")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    ParkFieldHelp(
                        text: "A short, factual intro in your own words: what kind of park it is and what it is known for. Prices and opening times have their own pages.",
                        counter: (session.park.description?.count ?? 0, ParkTextField.description.maxLength)
                    )
                    Text("Light formatting works: `_italic_`, `**bold**` and lists that start with `-`. Headings are left out.")
                }
            }

            Section {
                GhostList(
                    items: facilities,
                    maxCount: ParkLimits.facilities,
                    rules: GhostListRules(blank: { "" }, isBlank: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                ) { item, context in
                    ParkTextInput(title: "Add a facility", text: item, field: .facility)
                        .focused(context.focus, equals: context.id)
                }
            } header: {
                Text("Facilities")
            } footer: {
                Text("What riders find on site. Type one per row; a new row appears as you go. Swipe a row to remove it.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var facilities: Binding<[String]> {
        Binding(
            get: { session.park.facilities ?? [] },
            set: { session.park.facilities = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - Links

/// The booking page, Instagram and the like, as a section of the contact page.
struct ParkLinksSection: View {
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        Group {
            Section {
                GhostList(
                    items: links,
                    maxCount: ParkLimits.links,
                    rules: GhostListRules(
                        blank: { ParkLink(kind: "", url: "") },
                        isBlank: { $0.kind.isEmpty && $0.url.isEmpty },
                        confirmDelete: { link in
                            let name = link.kind.isEmpty ? String(localized: "this link") : ParkFormatting.linkKind(link.kind)
                            return (String(localized: "Delete \(name)?"), String(localized: "This cannot be undone."))
                        }
                    )
                ) { link, context in
                    ParkLinkRow(
                        link: link,
                        context: context,
                        usedKinds: usedKinds(except: link.wrappedValue),
                        onNameCommitted: mergeDuplicates
                    )
                }
            } header: {
                Text("Links")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("One link per type: a second one with the same name replaces the first. Choose \"Other\" for a name of your own, like Webshop.")
                    if ParkLinkKinds.duplicateKinds(in: session.park.links ?? []).isEmpty == false {
                        Label("Two links share a name. Saving keeps the last one.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var links: Binding<[ParkLink]> {
        Binding(
            get: { session.park.links ?? [] },
            set: { session.park.links = $0.isEmpty ? nil : $0 }
        )
    }

    private func usedKinds(except link: ParkLink) -> Set<String> {
        let mine = ParkLinkKinds.normalizedKey(link.kind)
        let all = (session.park.links ?? []).map { ParkLinkKinds.normalizedKey($0.kind) }
        var used = Set(all.filter { !$0.isEmpty })
        if used.contains(mine), all.filter({ $0 == mine }).count <= 1 { used.remove(mine) }
        return used
    }

    /// A name that matches another link's: the first stays, with the address just typed.
    private func mergeDuplicates(_ link: ParkLink) {
        let key = ParkLinkKinds.normalizedKey(link.kind)
        guard !key.isEmpty, var all = session.park.links else { return }
        let matches = all.indices.filter { ParkLinkKinds.normalizedKey(all[$0].kind) == key }
        guard matches.count > 1 else { return }
        all[matches[0]] = link
        for index in matches.dropFirst().reversed() { all.remove(at: index) }
        session.park.links = all
    }
}

private struct ParkLinkRow: View {
    @Binding var link: ParkLink
    let context: GhostRowContext
    let usedKinds: Set<String>
    let onNameCommitted: (ParkLink) -> Void

    @State private var customMode: Bool
    @FocusState private var nameFocused: Bool

    init(link: Binding<ParkLink>, context: GhostRowContext, usedKinds: Set<String>, onNameCommitted: @escaping (ParkLink) -> Void) {
        _link = link
        self.context = context
        self.usedKinds = usedKinds
        self.onNameCommitted = onNameCommitted
        let kind = link.wrappedValue.kind
        _customMode = State(initialValue: !kind.isEmpty && !ParkLinkKinds.isPreset(kind))
    }

    private var isPreset: Bool { ParkLinkKinds.isPreset(link.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                kindMenu
                TextField("Paste the address", text: urlBinding)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused(context.focus, equals: context.id)
            }
            if customMode || (!link.kind.isEmpty && !isPreset) {
                TextField("Name, for example Webshop", text: nameBinding)
                    .focused($nameFocused)
                    .font(.subheadline)
                    .onChange(of: nameFocused) { old, new in
                        if old, !new { onNameCommitted(link) }
                    }
            } else if link.kind.isEmpty, !link.url.isEmpty {
                Text("Choose what this link is.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var urlBinding: Binding<String> {
        Binding(
            get: { link.url },
            set: { new in
                link.url = ParkText.sanitizeTyping(new, field: .url)
                // A recognisable address picks its own type, until the person chose one.
                if link.kind.isEmpty, !customMode, let detected = ParkLinkKinds.detect(url: link.url),
                   !usedKinds.contains(detected) {
                    link.kind = detected
                }
            }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { link.kind },
            set: { link.kind = ParkText.sanitizeTyping($0, field: .label) }
        )
    }

    private var kindMenu: some View {
        Menu {
            ForEach(ParkLinkKinds.presets, id: \.self) { kind in
                let isCurrent = ParkLinkKinds.normalizedKey(link.kind) == kind
                Button {
                    customMode = false
                    link.kind = kind
                } label: {
                    if isCurrent { Label(ParkFormatting.linkKind(kind), systemImage: "checkmark") } else { Text(ParkFormatting.linkKind(kind)) }
                }
                .disabled(usedKinds.contains(kind) && !isCurrent)
            }
            Divider()
            Button("Other…") {
                customMode = true
                if isPreset { link.kind = "" }
                nameFocused = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(kindTitle).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(link.kind.isEmpty && !customMode ? Color.rpplAccent : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.rpplFill, in: Capsule())
            .fixedSize()
        }
    }

    private var kindTitle: String {
        if link.kind.isEmpty { return customMode ? String(localized: "Other") : String(localized: "Type") }
        return isPreset ? ParkFormatting.linkKind(link.kind) : String(localized: "Other")
    }
}
