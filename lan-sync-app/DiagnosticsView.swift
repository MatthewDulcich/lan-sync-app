import SwiftUI

final class DiagnosticsModel: ObservableObject {
    static let shared = DiagnosticsModel()
    @Published var isHost: Bool = false
    @Published var sessionID: String = ""
    @Published var epoch: UInt64 = 0
    @Published var hostID: String = ""
    @Published var latestSeq: UInt64 = 0
    @Published var peers: [String] = []
    @Published var bytesInPerSec: Double = 0
    @Published var bytesOutPerSec: Double = 0
    @Published var prefetchHits: Int = 0
    @Published var prefetchMisses: Int = 0
    @Published var imagesDedupSavedBytes: Int64 = 0
}

struct DiagnosticsView: View {
    @EnvironmentObject var diag: DiagnosticsModel
    var body: some View {
        Form {
            Section("Session") {
                LabeledContent("SessionID", value: diag.sessionID)
                LabeledContent("Epoch", value: String(diag.epoch))
                LabeledContent("Host", value: diag.hostID)
                LabeledContent("Is Host", value: String(diag.isHost))
                LabeledContent("Latest Seq", value: String(diag.latestSeq))
            }
            Section("Peers") {
                if diag.peers.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(diag.peers, id: \.self) { p in Text(p) }
            }
            Section("Throughput") {
                LabeledContent("Bytes In / s", value: String(format: "%.1f", diag.bytesInPerSec))
                LabeledContent("Bytes Out / s", value: String(format: "%.1f", diag.bytesOutPerSec))
            }
            Section("Prefetch") {
                LabeledContent("Hits", value: String(diag.prefetchHits))
                LabeledContent("Misses", value: String(diag.prefetchMisses))
            }
            Section("Dedup") {
                LabeledContent("Saved bytes", value: String(diag.imagesDedupSavedBytes))
            }
        }
        .navigationTitle("Diagnostics")
    }
}