// Replicator.swift (updated) — applies ops to SwiftData with LWW + claim semantics and idempotency.
// Inject your SwiftData ModelContext once using ContextBridge overlay.

import Foundation
import SwiftData

@MainActor
final class Replicator {
    static let shared = Replicator()
    private init() {}

    private var ctx: ModelContext?
    private var applied: Set<UUID> = [] // idempotency by opId (can be LRU in production)

    func injectContext(_ ctx: ModelContext) {
        self.ctx = ctx
    }

    // Convenience if views still call enqueueLocal
    func enqueueLocal(_ op: Op) {
        SessionManager.shared?.propose(op)
    }

    // Apply received/broadcast op (host-ordered by seq) or optimistic local op
    func apply(op: Op) {
        guard let ctx = ctx else {
            print("Replicator: no ModelContext injected")
            return
        }
        // Idempotency
        if applied.contains(op.opId) { return }
        applied.insert(op.opId)

        // Fetch existing record if any
        func fetch(_ id: UUID) -> Unit? {
            let desc = FetchDescriptor<Unit>(predicate: #Predicate { $0.id == id }, sortBy: [])
            return try? ctx.fetch(desc).first
        }

        switch op.kind {
        case .createUnit:
            guard fetch(op.recordID) == nil else { break }
            let u = Unit(id: op.recordID,
                         answer: op.fields?["answer"]?.stringValue,
                         eventDate: (op.fields?["eventDate"]?.dateValue),
                         eventName: op.fields?["eventName"]?.stringValue,
                         blobHash: op.blobHash,
                         isVerified: false,
                         isProcessing: false,
                         isChallenged: false,
                         isIllegible: false,
                         questionNumber: Int16(op.fields?["questionNumber"]?.intValue ?? 0),
                         teamClub: op.fields?["teamClub"]?.stringValue,
                         teamCode: op.fields?["teamCode"]?.stringValue,
                         teamName: op.fields?["teamName"]?.stringValue,
                         timeStamp: Date(),
                         lastEditor: op.authorDevice)
            ctx.insert(u)

        case .deleteUnit:
            if let u = fetch(op.recordID) {
                ctx.delete(u)
            }

        case .attachImage:
            if let u = fetch(op.recordID) {
                u.blobHash = op.blobHash
                u.timeStamp = Date()
                u.lastEditor = op.authorDevice
            }

        case .verifySet:
            if let u = fetch(op.recordID), let v = op.boolValue {
                if shouldApplyLWW(incoming: op.time, current: u.timeStamp) {
                    u.isVerified = v
                    u.timeStamp = Date()
                    u.lastEditor = op.authorDevice
                }
            }

        case .challengeSet:
            if let u = fetch(op.recordID), let v = op.boolValue {
                if shouldApplyLWW(incoming: op.time, current: u.timeStamp) {
                    u.isChallenged = v
                    u.timeStamp = Date()
                    u.lastEditor = op.authorDevice
                }
            }

        case .illegibleSet:
            if let u = fetch(op.recordID), let v = op.boolValue {
                if shouldApplyLWW(incoming: op.time, current: u.timeStamp) {
                    u.isIllegible = v
                    u.timeStamp = Date()
                    u.lastEditor = op.authorDevice
                }
            }

        case .editFields:
            if let u = fetch(op.recordID), let f = op.fields, shouldApplyLWW(incoming: op.time, current: u.timeStamp) {
                if case let .string(v)? = f["answer"] { u.answer = v }
                if case let .string(v)? = f["eventName"] { u.eventName = v }
                if case let .date(v)? = f["eventDate"] { u.eventDate = v }
                if case let .int(v)? = f["questionNumber"] { u.questionNumber = Int16(v) }
                if case let .string(v)? = f["teamClub"] { u.teamClub = v }
                if case let .string(v)? = f["teamCode"] { u.teamCode = v }
                if case let .string(v)? = f["teamName"] { u.teamName = v }
                u.timeStamp = Date()
                u.lastEditor = op.authorDevice
            }

        case .claim:
            if let u = fetch(op.recordID) {
                // First-writer-wins via op order: if already processing and lease active, ignore
                if u.isProcessing, LeaseManager.shared.isActive(recordID: op.recordID) {
                    break
                }
                u.isProcessing = true
                u.lastEditor = op.claimOwner ?? op.authorDevice
                u.timeStamp = Date()
                // Default lease 5 minutes (adjust as needed)
                LeaseManager.shared.grant(recordID: op.recordID, owner: u.lastEditor ?? op.authorDevice, seconds: 300)
            }

        case .unclaim:
            if let u = fetch(op.recordID) {
                u.isProcessing = false
                u.timeStamp = Date()
                u.lastEditor = op.authorDevice
                LeaseManager.shared.revoke(recordID: op.recordID)
            }
        }

        do { try ctx.save() } catch {
            print("Replicator save error: \(error)")
        }
    }

    private func shouldApplyLWW(incoming: Date, current: Date) -> Bool {
        return incoming >= current
    }
}

// MARK: - FieldValue helpers
extension FieldValue {
    var stringValue: String? { if case .string(let v) = self { return v } else { return nil } }
    var intValue: Int? { if case .int(let v) = self { return v } else { return nil } }
    var dateValue: Date? { if case .date(let v) = self { return v } else { return nil } }
}
