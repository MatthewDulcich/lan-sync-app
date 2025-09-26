import SwiftUI
import SwiftData

struct UnitDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var session: SessionManager

    let recordID: UUID
    @Query private var items: [Unit]

    init(recordID: UUID) {
        self.recordID = recordID
        self._items = Query(filter: #Predicate<Unit> { $0.id == recordID })
    }

    var body: some View {
        if let item = items.first {
            Form {
                Section("Status") {
                    Toggle("Verified", isOn: Binding(get: { item.isVerified }, set: { v in
                        session.setVerified(recordID: item.id, value: v)
                    }))
                    Toggle("Challenged", isOn: Binding(get: { item.isChallenged }, set: { v in
                        session.setChallenged(recordID: item.id, value: v)
                    }))
                    Toggle("Illegible", isOn: Binding(get: { item.isIllegible }, set: { v in
                        session.setIllegible(recordID: item.id, value: v)
                    }))
                }
                Section("Details") {
                    TextField("Answer", text: Binding(get: { item.answer ?? "" }, set: { t in
                        session.editFields(recordID: item.id, changes: ["answer": .string(t)])
                    }))
                    TextField("Event Name", text: Binding(get: { item.eventName ?? "" }, set: { t in
                        session.editFields(recordID: item.id, changes: ["eventName": .string(t)])
                    }))
                    Text("Question #: \(item.questionNumber)")
                    Text("Team: \(item.teamName ?? "—") (\(item.teamCode ?? "—"))")
                    Text("Last editor: \(item.lastEditor ?? "—")")
                }
                Section("Image") {
                    if let hash = item.blobHash {
                        HStack {
                            Text("Blob: \(hash.prefix(10))…")
                            Spacer()
                            Button("Fetch Full") { session.prefetcher.fetchNow(blobHash: item.blobHash) }
                        }
                    } else {
                        Text("None attached")
                    }
                }
            }
            .navigationTitle(item.eventName ?? "Record")
        } else {
            Text("Record not found").foregroundStyle(.secondary)
        }
    }
}