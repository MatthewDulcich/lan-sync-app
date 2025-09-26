import Foundation

final class LeaseManager {
    static let shared = LeaseManager()
    private init() {}

    struct Lease {
        var recordID: UUID
        var owner: String
        var expiresAt: Date
    }

    private var leases: [UUID: Lease] = [:]

    func grant(recordID: UUID, owner: String, seconds: TimeInterval) {
        leases[recordID] = Lease(recordID: recordID, owner: owner, expiresAt: Date().addingTimeInterval(seconds))
    }

    func revoke(recordID: UUID) { leases.removeValue(forKey: recordID) }

    func isActive(recordID: UUID) -> Bool {
        guard let l = leases[recordID] else { return false }
        if l.expiresAt < Date() { leases.removeValue(forKey: recordID); return false }
        return true
    }
}
