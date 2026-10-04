import RpplCore
import SwiftUI

struct ParkPricesPage: View {
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        Form {
            ParkPageIntro(
                page: .prices,
                text: "What riders pay. Type each price like the park's own site does and we read the currency and the format for you."
            )
            Section {
                GhostList(
                    items: prices,
                    maxCount: ParkLimits.prices,
                    rules: GhostListRules(
                        blank: { ParkPrice(name: "") },
                        isBlank: { $0 == ParkPrice(name: "") },
                        confirmDelete: { price in
                            let name = price.name.isEmpty ? String(localized: "this price") : price.name
                            return (String(localized: "Delete \(name)?"), String(localized: "This cannot be undone."))
                        }
                    )
                ) { price, context in
                    ParkPriceRow(price: price, context: context, defaultCurrency: defaultCurrency)
                }
            } header: {
                Text("Prices")
            } footer: {
                Text("Examples: `€12,50`, `12.50`, `€7 pp` for per person, `€10 per hour`, `-€3` for a discount. One price per row; a new row appears as you go.")
            }
        }
        .navigationTitle("Prices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var prices: Binding<[ParkPrice]> {
        Binding(
            get: { session.park.prices ?? [] },
            set: { session.park.prices = $0.isEmpty ? nil : $0 }
        )
    }

    /// New prices follow the currency of the ones already there, else the device's.
    private var defaultCurrency: String {
        (session.park.prices ?? []).compactMap(\.currency).first ?? Locale.current.currency?.identifier ?? "EUR"
    }
}

private struct ParkPriceRow: View {
    @Binding var price: ParkPrice
    let context: GhostRowContext
    let defaultCurrency: String
    @Environment(ParkEditorSession.self) private var session

    @State private var text: String
    @State private var problem: LocalizedStringKey?

    init(price: Binding<ParkPrice>, context: GhostRowContext, defaultCurrency: String) {
        _price = price
        self.context = context
        self.defaultCurrency = defaultCurrency
        _text = State(initialValue: ParkFormatting.priceInputText(price.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ParkTextInput(
                    title: context.isGhost ? "Add a price" : "Name",
                    text: $price.name,
                    field: .label
                )
                .textInputAutocapitalization(.sentences)
                .focused(context.focus, equals: context.id)
                TextField("Price", text: $text, prompt: Text(verbatim: "€0,00"))
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .onChange(of: text) { _, new in read(new) }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if let index = context.index {
                Button {
                    session.path.append(.price(index))
                } label: {
                    HStack {
                        Text(ParkFormatting.priceDetail(price) ?? String(localized: "Add details"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// Turns what was typed into the numbers behind it, and says so kindly when it cannot.
    private func read(_ typed: String) {
        let clean = ParkText.sanitizeTyping(typed, field: .label)
        if clean != typed { text = clean }
        switch ParkPriceParser.parse(clean) {
        case .empty:
            price.amount = nil
            problem = nil
        case .price(let parsed):
            price.amount = parsed.amount
            price.currency = parsed.currency ?? price.currency ?? defaultCurrency
            if let per = parsed.per { price.per = per }
            problem = nil
        case .invalid(let reason):
            price.amount = nil
            problem = switch reason {
            case .severalAmounts: "One price per row. Add the others as their own rows."
            case .tooLarge: "That is a lot. Check the amount."
            case .tooManyDecimals: "Prices have at most two decimals."
            case .unreadable: "Try something like €12,50 or 12.50."
            }
        }
    }
}

struct ParkPriceDetailPage: View {
    let index: Int
    @Environment(ParkEditorSession.self) private var session

    private static let durations = [30, 45, 60, 80, 90, 120, 180, 240]
    private static let currencies = ["EUR", "USD", "GBP", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF"]

    private var price: Binding<ParkPrice> {
        Binding(
            get: { session.park.prices?[safe: index] ?? ParkPrice(name: "") },
            set: { new in
                if session.park.prices?.indices.contains(index) == true { session.park.prices?[index] = new }
            }
        )
    }

    var body: some View {
        if let current = session.park.prices?[safe: index] {
            Form {
                Section {
                    LabeledContent("Price", value: ParkFormatting.price(current) ?? String(localized: "No amount yet"))
                    Picker("Currency", selection: currency) {
                        ForEach(currencyOptions(current), id: \.self) { code in
                            Text(ParkFormatting.currencyName(code)).tag(code)
                        }
                    }
                } footer: {
                    Text("Change the amount on the list. A discount is a negative amount, like -€3.")
                }

                Section {
                    Picker("Charged per", selection: per) {
                        Text("Not specified").tag("")
                        Text("Person").tag(ParkPriceUnit.person)
                        Text("Hour").tag(ParkPriceUnit.hour)
                        Text("Day").tag(ParkPriceUnit.day)
                        Text("Session").tag(ParkPriceUnit.session)
                        if let other = current.per, !ParkPriceUnit.all.contains(other) { Text(other).tag(other) }
                    }
                    Picker("Covers", selection: minutes) {
                        Text("Not specified").tag(0)
                        ForEach(durationOptions(current), id: \.self) { value in
                            Text(ParkFormatting.minutes(value)).tag(value)
                        }
                    }
                } header: {
                    Text("What it covers")
                } footer: {
                    Text(coverFooter(current))
                }

                Section {
                    ParkTextInput(
                        title: "For example adults, or own gear",
                        text: price.note.orEmpty,
                        field: .note,
                        axis: .vertical,
                        lines: 1...4
                    )
                } header: {
                    Text("Note")
                } footer: {
                    Text("Optional. Who the price is for or what is included. Shown under the name.")
                }

                Section {
                    Button("Delete price", systemImage: "trash", role: .destructive) {
                        let name = current.name.isEmpty ? String(localized: "this price") : current.name
                        session.askToDelete(
                            title: String(localized: "Delete \(name)?"),
                            message: String(localized: "This cannot be undone.")
                        ) {
                            session.path.removeLast()
                            session.park.prices?.remove(at: index)
                            if session.park.prices?.isEmpty == true { session.park.prices = nil }
                        }
                    }
                }
            }
            .navigationTitle(current.name.isEmpty ? String(localized: "Price") : current.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func coverFooter(_ price: ParkPrice) -> String {
        if let perHour = price.amountPerHour, let code = price.currency {
            let amount = perHour.formatted(.currency(code: code))
            return String(localized: "That comes to \(amount) per hour.")
        }
        return String(localized: "Optional. Fill in how long the price covers (for example 90 minutes for a block) and the app can work out the price per hour.")
    }

    private func durationOptions(_ price: ParkPrice) -> [Int] {
        var options = Self.durations
        if let minutes = price.minutes, !options.contains(minutes) { options.append(minutes) }
        return options.sorted()
    }

    private func currencyOptions(_ price: ParkPrice) -> [String] {
        var options = Self.currencies
        if let code = price.currency, !options.contains(code) { options.append(code) }
        return options
    }

    private var currency: Binding<String> {
        Binding(
            get: { price.wrappedValue.currency ?? Locale.current.currency?.identifier ?? "EUR" },
            set: { price.wrappedValue.currency = $0 }
        )
    }

    private var per: Binding<String> {
        Binding(
            get: { price.wrappedValue.per ?? "" },
            set: { price.wrappedValue.per = $0.isEmpty ? nil : $0 }
        )
    }

    private var minutes: Binding<Int> {
        Binding(
            get: { price.wrappedValue.minutes ?? 0 },
            set: { price.wrappedValue.minutes = $0 == 0 ? nil : $0 }
        )
    }
}
