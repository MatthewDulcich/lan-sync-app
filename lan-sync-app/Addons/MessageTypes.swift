import Foundation

enum MsgType: String, Codable {
    case hello, heartbeat
    case opPropose, opAccept, opBroadcast
    case catchUpRequest, catchUpBatch, snapshot
    case hostClaim, hostHandover
    case error
}

struct HelloMsg: Codable {
    var sessionID: String
    var deviceID: String
    var epochSeen: UInt64
    var userDisplayName: String
}

struct HeartbeatMsg: Codable {
    var sessionID: String
    var epoch: UInt64
    var hostID: String
    var latestSeq: UInt64
    var time: Date
}

struct CatchUpRequest: Codable {
    var fromSeq: UInt64
}

struct CatchUpBatch: Codable {
    var epoch: UInt64
    var ops: [Op]
    var latestSeq: UInt64
}

struct HostClaimMsg: Codable {
    var candidateHostID: String
    var newEpoch: UInt64
}

struct HostHandoverMsg: Codable {
    var newHostID: String
    var newEpoch: UInt64
}

struct FramedMessage: Codable {
    var type: MsgType
    var payload: Data? // JSON of the actual payload type
}

extension JSONEncoder {
    static let lansync: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let lansync: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
