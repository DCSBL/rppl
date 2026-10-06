import RpplCore
import SwiftUI

struct ParkPricesPage: View {
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        Form {
            ParkPageIntro(
                page: .prices,
                text: "What riders pay. Add a name, then one or more amounts: skis at €10 for 1 hour and €15 for 2 hours are one price with two amounts."
            )
            Section {
                GhostList(
                    items: prices,
                    maxCount: ParkLimits.prices,
                    rules: GhostListRules(
                        blank: { ParkPrice(name: "") },
                        isBlank: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.options.isEmpty },
                        confirmDelete: { price in
                            let name = price.name.isEmpty ? String(localized: "this price") : price.name
                            return (String(localized: "Delete \(name)?"), String(localized: "This cannot be undone."))
                        }
                    )
                ) { price, context in
                    ParkPriceRow(price: price, context: context)
                }
            } header: {
                Text("Prices")
            } footer: {
                Text("Type a name to add a price, for example Day pass or Wetsuit rental. Tap the line under a name to fill in its amounts.")
            }
        }
        .keyboardDoneButton()
        .navigationTitle("Prices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var prices: Binding<[ParkPrice]> {
        Binding(
            get: { session.park.prices ?? [] },
            set: { session.park.prices = $0.isEmpty ? nil : $0 }
        )
    }
}

private struct ParkPriceRow: View {
    @Binding var price: ParkPrice
    let context: GhostRowContext
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ParkTextInput(
                title: context.isGhost ? "Add a price" : "Name",
                text: $price.name,
                field: .label
            )
            .textInputAutocapitalization(.sentences)
            .focused(context.focus, equals: context.id)
            if let index = context.index {
                Button {
                    session.path.append(.price(index))
                } label: {
                    HStack {
                        Text(ParkFormatting.priceSummary(price) ?? String(localized: "Add amounts"))
                            .font(.footnote)
                            .foregroundStyle(ParkFormatting.priceSummary(price) == nil ? Color.rpplAccent : .secondary)
                            .lineLimit(3)
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
}

// MARK: - One price with its amounts

struct ParkPriceDetailPage: View {
    let index: Int
    @Environment(ParkEditorSession.self) private var session

    private var price: Binding<ParkPrice> {
        Binding(
            get: { session.park.prices?[safe: index] ?? ParkPrice(name: "") },
            set: { new in
                if session.park.prices?.indices.contains(index) == true { session.park.prices?[index] = new }
            }
        )
    }

    /// New amounts follow the currency of the other prices, else the device's.
    private var defaultCurrency: String {
        (session.park.prices ?? []).compactMap { ParkFormatting.currency(of: $0) }.first
            ?? ParkFormatting.defaultCurrencyCode
    }

    var body: some View {
        if let current = session.park.prices?[safe: index] {
            Form {
                Section {
                    ParkTextInput(title: "For example Skis", text: price.name, field: .label)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Name")
                }

                Section {
                    GhostList(
                        items: options,
                        maxCount: ParkLimits.priceOptions,
                        rules: GhostListRules(blank: { ParkPriceOption() }, isBlank: { $0.isBlank })
                    ) { option, context in
                        ParkPriceOptionRow(option: option, context: context, defaultCurrency: defaultCurrency)
                    }
                } header: {
                    Text("Amounts")
                } footer: {
                    Text("One row per amount: €10 per hour, €15 per 2 hours. A discount is a negative amount, like -3. Swipe a row to remove it.")
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
            .keyboardDoneButton()
            .navigationTitle(current.name.isEmpty ? String(localized: "Price") : current.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var options: Binding<[ParkPriceOption]> {
        Binding(
            get: { session.park.prices?[safe: index]?.options ?? [] },
            set: { new in
                if session.park.prices?.indices.contains(index) == true { session.park.prices?[index].options = new }
            }
        )
    }
}

private struct ParkPriceOptionRow: View {
    @Binding var option: ParkPriceOption
    let context: GhostRowContext
    let defaultCurrency: String

    private static let currencies = ["EUR", "USD", "GBP", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF"]

    @State private var text: String
    @State private var problem: LocalizedStringKey?
    @State private var customUnit: Bool

    init(option: Binding<ParkPriceOption>, context: GhostRowContext, defaultCurrency: String) {
        _option = option
        self.context = context
        self.defaultCurrency = defaultCurrency
        _text = State(initialValue: ParkFormatting.amountInputText(option.wrappedValue))
        let per = option.wrappedValue.per
        _customUnit = State(initialValue: per != nil && !ParkPriceUnit.all.contains(per ?? ""))
    }

    private var currency: String { option.currency ?? defaultCurrency }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                currencyMenu
                TextField("Amount", text: $text, prompt: Text(verbatim: "0,00"))
                    .keyboardType(.numbersAndPunctuation)
                    .focused(context.focus, equals: context.id)
                    .onChange(of: text) { _, new in read(new) }
            }
            HStack(spacing: 10) {
                unitMenu
                if customUnit {
                    TextField("For example per season", text: unitText)
                        .font(.subheadline)
                }
            }
            TextField("For whom or what (optional)", text: noteText)
                .font(.subheadline)
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var currencyMenu: some View {
        Menu {
            ForEach(Self.currencies + (Self.currencies.contains(currency) ? [] : [currency]), id: \.self) { code in
                Button(ParkFormatting.currencyName(code)) { option.currency = code }
            }
        } label: {
            pill(currency)
        }
    }

    private var unitMenu: some View {
        Menu {
            Button("Just this amount") {
                customUnit = false
                option.per = nil
            }
            ForEach(ParkPriceUnit.all, id: \.self) { unit in
                Button(ParkFormatting.perText(unit) ?? unit) {
                    customUnit = false
                    option.per = unit
                }
            }
            Button("Other…") {
                customUnit = true
                if ParkPriceUnit.all.contains(option.per ?? "") { option.per = nil }
            }
        } label: {
            pill(unitTitle)
        }
    }

    private var unitTitle: String {
        if customUnit { return String(localized: "Other") }
        return ParkFormatting.perText(option.per) ?? String(localized: "Per…")
    }

    private func pill(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.rpplFill, in: Capsule())
        .fixedSize()
    }

    private var unitText: Binding<String> {
        Binding(
            get: { option.per ?? "" },
            set: {
                let clean = ParkText.sanitizeTyping($0, field: .label)
                option.per = clean.isEmpty ? nil : clean
            }
        )
    }

    private var noteText: Binding<String> {
        Binding(
            get: { option.note ?? "" },
            set: {
                let clean = ParkText.sanitizeTyping($0, field: .note)
                option.note = clean.isEmpty ? nil : clean
            }
        )
    }

    /// Turns what was typed into the exact amount, and says so kindly when it cannot.
    private func read(_ typed: String) {
        switch ParkPriceParser.parse(typed) {
        case .empty:
            option.amount = nil
            problem = nil
        case .amount(let parsed):
            option.amount = parsed.text
            option.currency = option.currency ?? defaultCurrency
            problem = nil
        case .invalid(let reason):
            option.amount = nil
            problem = switch reason {
            case .severalAmounts: "One amount per row. Add the others as their own rows."
            case .tooLarge: "That is a lot. Check the amount."
            case .tooManyDecimals: "Amounts have at most two decimals."
            case .unreadable: "Try something like 12,50 or 12.50."
            }
        }
    }
}
