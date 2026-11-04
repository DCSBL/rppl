import RpplCore
import SwiftUI
import UniformTypeIdentifiers

/// Debug: the parks to review for towers, the request that lists them and the results to share.
struct TowerReviewView: View {
    private var store: TowerReviewStore { .shared }
    private var parkStore: ParkStore { .shared }

    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        List {
            Section {
                if let request = store.request {
                    if let note = request.note, !note.isEmpty {
                        Text(note)
                    }
                    Text("\(request.parks.count) parks requested on \(request.createdAt)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Forget request", role: .destructive) { store.clearRequest() }
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import request…", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Request")
            } footer: {
                Text(store.request == nil
                    ? "Without a request file every park without a traced cable is listed."
                    : "The parks below come from the request file.")
            }

            Section {
                Button {
                    store.shareResults()
                } label: {
                    Label("Share results", systemImage: "square.and.arrow.up")
                }
                .disabled(store.labels.labelCount == 0)
                Text("\(store.labels.labelCount) labels in \(store.labels.reviewedParkIDs.count) parks · \(store.snapshotCount) photos · \(store.mapCount) maps · \(store.closeupCount) close-ups")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let progress = store.extrasProgress {
                    ProgressView(value: Double(progress.done), total: Double(max(1, progress.total))) {
                        Text("Fetching \(progress.done) of \(progress.total)…")
                    }
                } else if store.missingExtras > 0 {
                    Button {
                        Task { await store.fetchExtras() }
                    } label: {
                        Label("Fetch maps and close-ups (\(store.missingExtras))", systemImage: "square.stack.3d.down.right")
                    }
                }
                if let error = store.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Results")
            } footer: {
                Text("The results zip holds every verdict on this phone (tower-labels.json) and the satellite photo of every \"Find towers\", so the training set can be built without a Mac. \"Fetch maps and close-ups\" adds the plain map of each photo (its water tells the detector where towers can stand) and a zoomed photo of every tower and the hardest rejected guesses. Share it again any time; the newest copy is complete.")
            }

            Section("Parks") {
                ForEach(rows) { row in
                    if let park = row.park {
                        NavigationLink {
                            TowerReviewMapView(park: park)
                        } label: {
                            parkRow(row)
                        }
                    } else {
                        parkRow(row)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Review towers")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                try store.importRequest(from: url)
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("Could not read the request", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private var rows: [TowerReviewStore.Row] { store.rows(entries: parkStore.entries) }

    private func parkRow(_ row: TowerReviewStore.Row) -> some View {
        let towers = store.labels.count(.tower, in: row.id)
        let none = store.labels.count(.notTower, in: row.id)
        let hidden = store.labels.count(.notVisible, in: row.id)
        let unsure = store.labels.count(.unsure, in: row.id)
        let reviewed = towers + none + hidden + unsure > 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                if row.park == nil {
                    Text("Not on this phone").font(.caption).foregroundStyle(.secondary)
                } else if let reason = row.reason, !reason.isEmpty {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if reviewed {
                Text("\(towers) · \(none) · \(unsure)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("\(towers) towers, \(none) no tower, \(unsure) unsure"))
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }
}
