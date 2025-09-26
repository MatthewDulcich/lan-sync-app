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
                        Image(systemName: "photo.badge.plus")
                    }
                }
                .contextMenu {
                    Button("Claim/Lock") { session.claim(recordID: item.id) }
                    Button("Unclaim") { session.unclaim(recordID: item.id) }
                    Button("Toggle Verified") { session.setVerified(recordID: item.id, value: !item.isVerified) }
                    Button("Fetch Image") { session.prefetcher.fetchNow(blobHash: item.blobHash) }
                    Button(role: .destructive) { session.deleteUnit(recordID: item.id) } label: { Label("Delete", systemImage: "trash") }
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
        // Use operation-based creation instead of direct SwiftData manipulation
        let initial: [String: FieldValue] = [
            "eventName": .string("Sample Event"),
            "questionNumber": .int(1),
            "teamClub": .string("Club A"),
            "teamCode": .string("A01"),
            "teamName": .string("Team A"),
            "answer": .string("Sample answer")
        ]
        session.createUnit(initial: initial)
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
