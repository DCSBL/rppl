import RpplCore
import SwiftUI

extension ParkEditorSession {
    func updateOpening(_ change: (inout ParkOpening) -> Void) {
        var opening = park.opening ?? ParkOpening()
        change(&opening)
        park.opening = opening
    }
}

struct ParkOpeningPage: View {
    @Environment(ParkEditorSession.self) private var session

    private var opening: ParkOpening { session.park.opening ?? ParkOpening() }

    var body: some View {
        Form {
            ParkPageIntro(
                page: .opening,
                text: "When is the park open? You can leave this empty: the park then shows \"Opening hours unknown\" until someone fills it in."
            )
            if !opening.isScheduleKnown {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Opening hours unknown").font(.subheadline.weight(.semibold))
                            Text("Nothing is filled in yet, so the park shows as unknown. That is fine when you do not know the hours.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                GhostList(
                    items: rules,
                    maxCount: ParkLimits.rules,
                    rules: GhostListRules(
                        blank: { ParkOpeningRule(open: "", close: "") },
                        isBlank: { $0.open.isEmpty && $0.close.isEmpty },
                        confirmDelete: { _ in
                            (String(localized: "Delete these opening hours?"), String(localized: "This cannot be undone."))
                        }
                    )
                ) { rule, context in
                    if context.isGhost {
                        GhostPlaceholderRow(title: "Add opening hours") {
                            let next = (opening.rules ?? []).count
                            rule.wrappedValue = ParkOpeningRule(open: "10:00", close: "18:00")
                            session.path.append(.rule(next))
                        }
                    } else if let index = context.index {
                        ParkHoursRow(summary: ParkFormatting.ruleSummary(rule.wrappedValue)) {
                            session.path.append(.rule(index))
                        }
                    }
                }
            } header: {
                Text("Opening hours")
            } footer: {
                Text("The hours riders can just show up. Add a row for every period with different hours: summer, winter, weekends, a holiday.")
            }

            Section {
                GhostList(
                    items: slots,
                    maxCount: ParkLimits.slots,
                    rules: GhostListRules(
                        blank: { ParkSlot(id: "", start: "", end: "") },
                        isBlank: { $0.start.isEmpty && $0.end.isEmpty },
                        confirmDelete: { _ in
                            (String(localized: "Delete this block?"), String(localized: "This cannot be undone."))
                        }
                    )
                ) { slot, context in
                    if context.isGhost {
                        GhostPlaceholderRow(title: "Add a block") {
                            let next = (opening.slots ?? []).count
                            slot.wrappedValue = ParkSlot(id: nextBlockID(), start: "10:00", end: "11:30")
                            session.path.append(.block(next))
                        }
                    } else if let index = context.index {
                        ParkHoursRow(summary: ParkFormatting.blockSummary(slot.wrappedValue, numbered: opening.numbered)) {
                            session.path.append(.block(index))
                        }
                    }
                }
            } header: {
                Text("Blocks")
            } footer: {
                Text("For parks that sell fixed time blocks, like 14:00 to 15:30. Skip this if riders can come and go within the opening hours.")
            }

            Section {
                Picker("Booking", selection: booking) {
                    Text("Not set").tag("")
                    Text("Required").tag("required")
                    Text("Optional").tag("optional")
                    Text("Not needed").tag("none")
                }
            } footer: {
                Text("Do riders have to book a time in advance?")
            }

            Section {
                ParkTextInput(
                    title: "Anything riders should know",
                    text: note,
                    field: .note,
                    axis: .vertical,
                    lines: 1...5
                )
            } header: {
                Text("Note")
            } footer: {
                ParkFieldHelp(
                    text: "Optional. For example \"Closed on windy days\" or \"Hours change in school holidays\".",
                    counter: (opening.note?.count ?? 0, ParkTextField.note.maxLength)
                )
            }

            if let count = opening.exceptions?.count, count > 0 {
                Section {
                    Label("\(count) announced changes are kept as they are", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Closures and extra hours cannot be edited here yet.")
                }
            }
        }
        .navigationTitle("Opening times")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var rules: Binding<[ParkOpeningRule]> {
        Binding(
            get: { session.park.opening?.rules ?? [] },
            set: { new in session.updateOpening { $0.rules = new.isEmpty ? nil : new } }
        )
    }

    private var slots: Binding<[ParkSlot]> {
        Binding(
            get: { session.park.opening?.slots ?? [] },
            set: { new in session.updateOpening { $0.slots = new.isEmpty ? nil : new } }
        )
    }

    private var booking: Binding<String> {
        Binding(
            get: { session.park.opening?.booking ?? "" },
            set: { new in session.updateOpening { $0.booking = new.isEmpty ? nil : new } }
        )
    }

    private var note: Binding<String> {
        Binding(
            get: { session.park.opening?.note ?? "" },
            set: { new in session.updateOpening { $0.note = new.isEmpty ? nil : new } }
        )
    }

    /// Blocks get their identifier from the editor: the next free number.
    private func nextBlockID() -> String {
        let used = (opening.slots ?? []).compactMap { Int($0.id) }
        return String((used.max() ?? 0) + 1)
    }
}

private struct ParkHoursRow: View {
    let summary: (title: String, detail: String?)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title).monospacedDigit().foregroundStyle(.primary)
                    if let detail = summary.detail {
                        Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - One set of opening hours

struct ParkRuleDetailPage: View {
    let index: Int
    @Environment(ParkEditorSession.self) private var session
    /// Set once deletion is confirmed; the rule is removed after this page is gone (see `onDisappear`).
    @State private var deleting = false

    private var rule: Binding<ParkOpeningRule> {
        Binding(
            get: { session.park.opening?.rules?[safe: index] ?? ParkOpeningRule(open: "10:00", close: "18:00") },
            set: { new in
                session.updateOpening {
                    if $0.rules?.indices.contains(index) == true { $0.rules?[index] = new }
                }
            }
        )
    }

    var body: some View {
        if let current = session.park.opening?.rules?[safe: index] {
            Form {
                Section {
                    ParkTextInput(title: "For example Summer", text: rule.label.orEmpty, field: .label)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Optional. A short name for this period or hour, like Summer, Weekends or Beginner hour.")
                }

                Section {
                    ParkTimePicker(title: "Opens", time: rule.open)
                    Toggle("Open until sunset", isOn: closesAtSunset)
                    if current.close.lowercased() != ParkClock.sunset {
                        ParkTimePicker(title: "Closes", time: rule.close)
                    }
                } header: {
                    Text("Hours")
                } footer: {
                    Text(hoursFooter(current))
                }

                ParkAppliesToSection(
                    months: rule.months,
                    days: rule.days,
                    dates: rule.dates
                )

                Section {
                    Button("Delete these hours", systemImage: "trash", role: .destructive) {
                        session.askToDelete(
                            title: String(localized: "Delete these opening hours?"),
                            message: String(localized: "This cannot be undone.")
                        ) {
                            deleting = true
                            session.path.removeLast()
                        }
                    }
                }
            }
            .navigationTitle(ParkFormatting.ruleSummary(current).title)
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                guard deleting else { return }
                session.updateOpening {
                    if $0.rules?.indices.contains(index) == true { $0.rules?.remove(at: index) }
                    if $0.rules?.isEmpty == true { $0.rules = nil }
                }
            }
        }
    }

    private var closesAtSunset: Binding<Bool> {
        Binding(
            get: { rule.wrappedValue.close.lowercased() == ParkClock.sunset },
            set: { rule.wrappedValue.close = $0 ? ParkClock.sunset : "18:00" }
        )
    }

    private func hoursFooter(_ rule: ParkOpeningRule) -> String {
        if rule.open == rule.close {
            return String(localized: "Opens and closes at the same time, which counts as open for 24 hours.")
        }
        if ParkClock.wrapsPastMidnight(open: rule.open, close: rule.close) {
            return String(localized: "Closes before it opens, so this runs past midnight into the next day.")
        }
        return String(localized: "Times follow the time zone of the park.")
    }
}

// MARK: - One block

struct ParkBlockDetailPage: View {
    let index: Int
    @Environment(ParkEditorSession.self) private var session
    /// Set once deletion is confirmed; the block is removed after this page is gone (see `onDisappear`).
    @State private var deleting = false

    private var slot: Binding<ParkSlot> {
        Binding(
            get: { session.park.opening?.slots?[safe: index] ?? ParkSlot(id: "", start: "10:00", end: "11:30") },
            set: { new in
                session.updateOpening {
                    if $0.slots?.indices.contains(index) == true { $0.slots?[index] = new }
                }
            }
        )
    }

    var body: some View {
        if let current = session.park.opening?.slots?[safe: index] {
            Form {
                Section {
                    ParkTimePicker(title: "Starts", time: slot.start)
                    ParkTimePicker(title: "Ends", time: slot.end)
                } header: {
                    Text("Times")
                } footer: {
                    Text("Times follow the time zone of the park.")
                }

                ParkAppliesToSection(
                    months: slot.months,
                    days: slot.days,
                    dates: slot.dates
                )

                Section {
                    Button("Delete this block", systemImage: "trash", role: .destructive) {
                        session.askToDelete(
                            title: String(localized: "Delete this block?"),
                            message: String(localized: "This cannot be undone.")
                        ) {
                            deleting = true
                            session.path.removeLast()
                        }
                    }
                }
            }
            .navigationTitle(ParkFormatting.slot(current))
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                guard deleting else { return }
                session.updateOpening {
                    if $0.slots?.indices.contains(index) == true { $0.slots?.remove(at: index) }
                    if $0.slots?.isEmpty == true { $0.slots = nil }
                }
            }
        }
    }
}

// MARK: - When hours apply

/// Months, days, a period and single dates: when a set of hours or a block counts. Everything on its
/// default means every day of the year.
struct ParkAppliesToSection: View {
    @Binding var months: [Int]?
    @Binding var days: [String]?
    @Binding var dates: [String]?

    var body: some View {
        Section {
            NavigationLink {
                ParkToggleListPage(
                    title: "Months",
                    footer: "Switch on the months these hours count in. With none or all switched on they count all year.",
                    options: (1...12).map { ($0, Calendar.current.standaloneMonthSymbols[$0 - 1].capitalized) },
                    selection: Binding(
                        get: { ParkDaySelection.monthSet(from: months) },
                        set: { months = ParkDaySelection.months(from: $0) }
                    ),
                    shortcuts: [
                        (String(localized: "All year"), Set(1...12)),
                        (String(localized: "Summer (Apr to Sep)"), Set(4...9)),
                        (String(localized: "Winter (Oct to Mar)"), Set([10, 11, 12, 1, 2, 3])),
                    ]
                )
            } label: {
                LabeledContent("Months", value: ParkFormatting.monthsSummary(months))
            }
            NavigationLink {
                ParkToggleListPage(
                    title: "Days",
                    footer: "Switch on the days these hours count on. With none or all switched on they count every day.",
                    options: ParkDaySelection.weekdayTokens.map { ($0, ParkFormatting.longDayName($0)) },
                    selection: Binding(
                        get: { ParkDaySelection.days(from: days) },
                        set: { days = ParkDaySelection.tokens(from: $0) }
                    ),
                    shortcuts: [
                        (String(localized: "Every day"), Set(ParkDaySelection.weekdayTokens)),
                        (String(localized: "Monday to Friday"), Set(["mon", "tue", "wed", "thu", "fri"])),
                        (String(localized: "Weekend"), Set(["sat", "sun"])),
                    ]
                )
            } label: {
                LabeledContent("Days", value: ParkFormatting.days(days) ?? String(localized: "Every day"))
            }
            NavigationLink {
                ParkDatesPage(dates: $dates)
            } label: {
                LabeledContent("Only on certain dates", value: datesSummary)
            }
        } header: {
            Text("Applies on")
        } footer: {
            Text("Leave everything as it is and these hours count every day of the year. Use \"Only on certain dates\" for a holiday or a special day with its own hours.")
        }
    }

    private var datesSummary: String {
        guard let dates, !dates.isEmpty else { return String(localized: "None") }
        return String(localized: "\(dates.count) dates")
    }
}

/// Single dates (holidays, special days) a set of hours counts on.
struct ParkDatesPage: View {
    @Binding var dates: [String]?

    var body: some View {
        Form {
            Section {
                GhostList(
                    items: Binding(
                        get: { dates ?? [] },
                        set: { dates = $0.isEmpty ? nil : $0 }
                    ),
                    maxCount: ParkLimits.dates,
                    rules: GhostListRules(blank: { "" }, isBlank: { $0.isEmpty })
                ) { date, context in
                    if context.isGhost {
                        GhostPlaceholderRow(title: "Add a date") { date.wrappedValue = ParkEditorDates.todayISO }
                    } else {
                        ParkDatePicker(title: "Date", iso: date)
                    }
                }
            } footer: {
                Text("The hours then count on these dates only, for example Christmas Day or Easter Monday. Swipe a date to remove it.")
            }
        }
        .navigationTitle("Certain dates")
        .navigationBarTitleDisplayMode(.inline)
    }
}
