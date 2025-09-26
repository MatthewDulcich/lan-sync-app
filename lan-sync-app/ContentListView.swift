import SwiftUI
import SwiftData

struct ContentListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Unit.timeStamp, order: .reverse)]) var items: [Unit]
    @State private var selection: Unit?
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var diag: DiagnosticsModel

    var body: some View {
        List(items, selection: $selection) { item in
            NavigationLink(value: item.id) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.eventName ?? "Untitled Event")
                            .font(.headline)
                        Text("Q# \(item.questionNumber) • Team: \(item.teamCode ?? "—")")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        Text("Verified: \(item.isVerified ? "Yes" : "No") • Processing: \(item.isProcessing ? "Yes" : "No")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let hash = item.blobHash, !hash.isEmpty {
                        Image(systemName: "photo")
                    } else {
                        Image(systemName: "photo.slash")
                    }
                }
                .contextMenu {
                    Button("Claim/Lock") { session.claim(recordID: item.id) }
                    Button("Unclaim") { session.unclaim(recordID: item.id) }
                    Button("Toggle Verified") { session.setVerified(recordID: item.id, value: !item.isVerified) }
                    Button("Fetch Image") { session.prefetcher.fetchNow(blobHash: item.blobHash) }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentEmptyStateView(addHandler: addFake)
            }
        }
        .navigationDestination(for: UUID.self) { id in
            UnitDetailView(recordID: id)
        }
    }

    private func addFake() {
        let u = Unit(id: UUID(),
                     answer: nil,
                     eventDate: .now,
                     eventName: "Sample Event",
                     blobHash: nil,
                     isVerified: false,
                     isProcessing: false,
                     isChallenged: false,
                     isIllegible: false,
                     questionNumber: 1,
                     teamClub: "Club A",
                     teamCode: "A01",
                     teamName: "Team A",
                     timeStamp: .now,
                     lastEditor: "Seeder@Device")
        context.insert(u)
        try? context.save()
    }
}

struct ContentEmptyStateView: View {
    var addHandler: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48))
            Text("No items yet")
            Button("Insert sample") { addHandler() }
        }
        .foregroundStyle(.secondary)
    }
}
