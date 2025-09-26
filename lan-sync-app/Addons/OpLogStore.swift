import Foundation

final class OpLogStore {
    static let shared = OpLogStore()

    private let fm = FileManager.default
    private let root: URL
    private let opsDir: URL
    private let checkpointsDir: URL

    private let encoder = JSONEncoder.lansync
    private let decoder = JSONDecoder.lansync

    private(set) var latestSeq: UInt64 = 0
    private var assignedOps: Set<UUID> = [] // simple idempotency cache (use LRU in production)

    private init() {
        root = fm.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("op-log", isDirectory: true)
        opsDir = root.appendingPathComponent("ops", isDirectory: true)
        checkpointsDir = root.appendingPathComponent("checkpoints", isDirectory: true)
        try? fm.createDirectory(at: opsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: checkpointsDir, withIntermediateDirectories: true)
        latestSeq = loadLatestSeq()
    }

    private func loadLatestSeq() -> UInt64 {
        // naive: scan ops dir for highest seq; in real app store an index
        let files = (try? fm.contentsOfDirectory(at: opsDir, includingPropertiesForKeys: nil)) ?? []
        let seqs = files.compactMap { url -> UInt64? in
            let name = url.deletingPathExtension().lastPathComponent
            if name.hasPrefix("op-") {
                return UInt64(name.dropFirst(3))
            }
            return nil
        }
        return seqs.max() ?? 0
    }

    func assignSeqAndAppend(_ op: inout Op, epoch: UInt64) throws -> UInt64 {
        guard assignedOps.insert(op.opId).inserted else { return op.seq ?? latestSeq }
        latestSeq &+= 1
        op.seq = latestSeq
        op.epoch = epoch
        let data = try encoder.encode(op)
        let url = opsDir.appendingPathComponent("op-\(latestSeq).json")
        try data.write(to: url, options: .atomic)
        return latestSeq
    }

    func ops(since seq: UInt64, limit: Int = 1000) -> [Op] {
        var out: [Op] = []
        var i = seq + 1
        while i <= latestSeq && out.count < limit {
            let url = opsDir.appendingPathComponent("op-\(i).json")
            if let data = try? Data(contentsOf: url),
               let op = try? decoder.decode(Op.self, from: data) {
                out.append(op)
            }
            i &+= 1
        }
        return out
    }

    struct Snapshot: Codable {
        var seq: UInt64
        var units: [UnitSnapshot]
    }
    struct UnitSnapshot: Codable {
        var id: UUID
        var answer: String?
        var eventDate: Date?
        var eventName: String?
        var blobHash: String?
        var isVerified: Bool
        var isProcessing: Bool
        var isChallenged: Bool
        var isIllegible: Bool
        var questionNumber: Int16
        var teamClub: String?
        var teamCode: String?
        var teamName: String?
        var timeStamp: Date
        var lastEditor: String?
    }

    func writeSnapshot(units: [Unit], seq: UInt64) throws -> URL {
        let snap = Snapshot(seq: seq, units: units.map {
            UnitSnapshot(id: $0.id, answer: $0.answer, eventDate: $0.eventDate, eventName: $0.eventName,
                         blobHash: $0.blobHash, isVerified: $0.isVerified, isProcessing: $0.isProcessing,
                         isChallenged: $0.isChallenged, isIllegible: $0.isIllegible, questionNumber: $0.questionNumber,
                         teamClub: $0.teamClub, teamCode: $0.teamCode, teamName: $0.teamName, timeStamp: $0.timeStamp,
                         lastEditor: $0.lastEditor)
        })
        let data = try encoder.encode(snap)
        let url = checkpointsDir.appendingPathComponent("checkpoint-\(seq).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func readSnapshot() -> Snapshot? {
        // return the highest checkpoint if exists
        let files = (try? fm.contentsOfDirectory(at: checkpointsDir, includingPropertiesForKeys: nil)) ?? []
        let pairs = files.compactMap { url -> (UInt64, URL)? in
            let name = url.deletingPathExtension().lastPathComponent
            if name.hasPrefix("checkpoint-"), let n = UInt64(name.replacingOccurrences(of: "checkpoint-", with: "")) {
                return (n, url)
            }
            return nil
        }
        guard let maxPair = pairs.max(by: { $0.0 < $1.0 }) else { return nil }
        guard let data = try? Data(contentsOf: maxPair.1) else { return nil }
        return try? decoder.decode(Snapshot.self, from: data)
    }
}
