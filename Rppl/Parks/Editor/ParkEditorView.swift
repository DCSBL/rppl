import RpplCore
import SwiftUI

/// Add or edit a park. A new park is walked through page by page; an existing park opens as a list of
/// pages to jump between. Either way every change is kept as a draft, so closing the app or the editor
/// never loses work, and the editor never closes without asking what to do with unsaved changes.
struct ParkEditorView: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: ParkEditorSession
    @State private var confirmClose = false
    @State private var saveError: String?

    /// `original` nil starts a new park. `draft` continues unsaved work.
    init(original: Park?, resuming draft: ParkEditDraft? = nil, onSaved: @escaping () -> Void = {}) {
        self.onSaved = onSaved
        _session = State(initialValue: ParkEditorSession(original: original, resuming: draft))
    }

    var body: some View {
        NavigationStack(path: $session.path) {
            root
                .navigationDestination(for: ParkEditorRoute.self) { route in destination(route) }
                .toolbar { toolbar }
                .navigationBarTitleDisplayMode(.inline)
        }
        .environment(session)
        .tint(Color.rpplAccent)
        .interactiveDismissDisabled(session.isDirty)
        .confirmationDialog("Keep your changes?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Save as draft") {
                session.saveDraftNow()
                dismiss()
            }
            Button("Discard changes", role: .destructive) {
                session.discardDraft()
                dismiss()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("A draft stays on this iPhone, so you can continue later from the Parks tab.")
        }
        .confirmationDialog(
            session.deletion?.title ?? "",
            isPresented: Binding(get: { session.deletion != nil }, set: { if !$0 { session.deletion = nil } }),
            titleVisibility: .visible,
            presenting: session.deletion
        ) { deletion in
            Button("Delete", role: .destructive) { deletion.perform() }
        } message: { deletion in
            Text(deletion.message)
        }
        .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .onChange(of: session.park) { session.scheduleDraftSave() }
        .onChange(of: session.step) { session.scheduleDraftSave() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.saveDraftNow() }
        }
    }

    // MARK: Root

    @ViewBuilder
    private var root: some View {
        if session.isGuided {
            ParkGuidedFlow(onSave: save)
        } else {
            ParkEditHub()
                .navigationTitle("Edit park")
        }
    }

    @ViewBuilder
    private func destination(_ route: ParkEditorRoute) -> some View {
        switch route {
        case .page(let page): ParkEditorPageView(page: page)
        case .cable(let index): ParkCableDetailPage(index: index)
        case .rule(let index): ParkRuleDetailPage(index: index)
        case .block(let index): ParkBlockDetailPage(index: index)
        case .price(let index): ParkPriceDetailPage(index: index)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", action: close)
        }
        if !session.isGuided {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(!session.issues.isEmpty || !session.isDirty)
            }
        }
    }

    // MARK: Actions

    private func close() {
        if session.isDirty {
            confirmClose = true
        } else {
            session.discardDraft()
            dismiss()
        }
    }

    private func save() {
        do {
            try session.save()
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// One page of the editor, whichever way it was reached.
struct ParkEditorPageView: View {
    let page: ParkEditorPage

    var body: some View {
        switch page {
        case .basics: ParkBasicsPage()
        case .contact: ParkContactPage()
        case .about: ParkAboutPage()
        case .cables: ParkCablesPage()
        case .opening: ParkOpeningPage()
        case .prices: ParkPricesPage()
        }
    }
}

// MARK: - Free editing

/// The pages of an existing park, each with a line on what is in it.
private struct ParkEditHub: View {
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        List {
            if !session.issues.isEmpty {
                ParkIssuesSection()
            }
            Section {
                ForEach(ParkEditorPage.allCases, id: \.self) { page in
                    NavigationLink(value: ParkEditorRoute.page(page)) {
                        ParkPageRow(page: page)
                    }
                }
            } header: {
                Text(session.park.name.isEmpty ? "Park" : session.park.name)
            } footer: {
                Text("Open a page to change it. Your changes are kept as a draft until you save.")
            }
        }
    }
}

private struct ParkPageRow: View {
    let page: ParkEditorPage
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.systemImage)
                .frame(width: 28)
                .foregroundStyle(Color.rpplAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                Text(ParkFormatting.pageSummary(page, park: session.finalized))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if session.issues(on: page).isEmpty {
                if session.isFilled(page) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .accessibilityLabel(Text("Filled in"))
                }
            } else {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    .accessibilityLabel(Text("Needs attention"))
            }
        }
    }
}

/// What stops saving, in plain words, with a way to the right page.
struct ParkIssuesSection: View {
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        Section {
            ForEach(Array(session.issues.enumerated()), id: \.offset) { _, issue in
                Button {
                    session.jump(to: ParkEditorPage.page(for: issue.section))
                } label: {
                    HStack {
                        Label(issue.message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
            }
        } header: {
            Text("To fix before saving")
        }
    }
}

// MARK: - Guided flow

private struct ParkGuidedFlow: View {
    let onSave: () -> Void
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        Group {
            switch session.currentStep {
            case .welcome: ParkWelcomeStep()
            case .page(let page): ParkEditorPageView(page: page)
            case .review: ParkReviewPage()
            }
        }
        .id(session.step)
        .transition(.opacity)
        .safeAreaInset(edge: .bottom) { bar }
        .navigationTitle(title)
    }

    private var title: LocalizedStringKey {
        switch session.currentStep {
        case .welcome: "New park"
        case .page(let page): page.title
        case .review: "Review"
        }
    }

    private var bar: some View {
        VStack(spacing: 10) {
            ProgressView(value: Double(session.step), total: Double(ParkEditorStep.guided.count - 1))
                .tint(Color.rpplAccent)
            HStack {
                if session.step > 0 {
                    Button("Back") { withAnimation { session.goToPrevious() } }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if session.currentStep == .review {
                    Button("Save park", systemImage: "checkmark.circle.fill", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .disabled(!session.issues.isEmpty)
                } else {
                    Button(nextTitle) { withAnimation { session.goToNext() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var nextTitle: LocalizedStringKey {
        switch session.currentStep {
        case .welcome: "Start"
        case .page(.basics): "Next"
        case .page(let page): session.isFilled(page) ? "Next" : "Skip"
        case .review: "Next"
        }
    }
}

private struct ParkWelcomeStep: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "figure.waterskiing")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.rpplAccent)
                    .accessibilityHidden(true)
                Text("Add a cable park")
                    .font(.largeTitle.bold())
                Text("A few short pages, one at a time. You can go back to change anything.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    point("checkmark.circle", "Only the name and the location are needed. Leave out what you do not know.")
                    point("tray.and.arrow.down", "Everything you fill in is kept as a draft. Close the app or the editor and continue later.")
                    point("globe", "Use the park's own website or what you saw on site. Please do not copy from other apps.")
                    point("paperplane", "When you are done you can share the park with Rppl, so everyone gets it.")
                }
            }
            .padding(20)
        }
    }

    private func point(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.rpplAccent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
        }
    }
}

// MARK: - Review

/// The last page of the guided flow: what is in, and what still needs a fix before saving.
struct ParkReviewPage: View {
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        List {
            if !session.issues.isEmpty {
                ParkIssuesSection()
            }
            Section {
                ForEach(ParkEditorPage.allCases, id: \.self) { page in
                    Button {
                        session.jump(to: page)
                    } label: {
                        HStack {
                            ParkPageRow(page: page)
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text(session.park.name.isEmpty ? "Your park" : session.park.name)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pages you left empty are just left out.")
                    if session.finalized.opening?.isScheduleKnown != true {
                        Text("Without opening times the park shows \"Opening hours unknown\".")
                    }
                    Text("You can still change everything afterwards from the park's menu.")
                }
            }
        }
    }
}
