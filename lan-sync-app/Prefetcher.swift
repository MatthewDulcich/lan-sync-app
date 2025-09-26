import Foundation

final class Prefetcher {
    static let shared = Prefetcher()
    private init() {}

    func fetchNow(blobHash: String?) {
        // Stub: implement BlobClient requests here.
        // For now, just log to diagnostics.
        guard let blobHash, !blobHash.isEmpty else { return }
        DiagnosticsModel.shared.prefetchMisses += 1 // pretend miss; implement real fetch later
    }
}