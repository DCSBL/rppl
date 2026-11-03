import RpplCore
import SwiftUI
import UniformTypeIdentifiers

/// Debug: the parks to review for towers, the request that lists them and the results to share.
struct MastReviewView: View {
    private var store: MastReviewStore { .shared }
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
                Text("\(store.labels.labelCount) labels in \(store.labels.reviewedParkIDs.count) parks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let error = store.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Results")
            } footer: {
                Text("The results file (mast-labels.json) holds every verdict on this phone; share it again any time, the newest copy is complete.")
            }

            Section("Parks") {
                ForEach(rows) { row in
                    if let park = row.park {
                        NavigationLink {
                            MastReviewMapView(park: park)
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

    private var rows: [MastReviewStore.Row] { store.rows(entries: parkStore.entries) }

    private func parkRow(_ row: MastReviewStore.Row) -> some View {
        let masts = store.labels.count(.mast, in: row.id)
        let none = store.labels.count(.notMast, in: row.id)
        let unsure = store.labels.count(.unsure, in: row.id)
        let reviewed = masts + none + unsure > 0
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
                Text("\(masts) · \(none) · \(unsure)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("\(masts) towers, \(none) no tower, \(unsure) unsure"))
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }
}
