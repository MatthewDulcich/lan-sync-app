import Foundation
import Network
import Combine

final class VerifierService: ObservableObject {
    static let shared = VerifierService()
    private init() {}

    private var conn: NWConnection?
    private var buffer = Data()

    @Published var latestEpoch: UInt64 = 0
    @Published var latestSeq: UInt64 = 0

    func connect(host: NWEndpoint.Host, port: NWEndpoint.Port, deviceID: String, userDisplayName: String, sessionID: String, epochSeen: UInt64) {
        let conn = NWConnection(host: host, port: port, using: .tcp)
        self.conn = conn
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let hello = HelloMsg(sessionID: sessionID, deviceID: deviceID, epochSeen: epochSeen, userDisplayName: userDisplayName)
                let payload = try? JSONEncoder.lansync.encode(hello)
                let msg = FramedMessage(type: .hello, payload: payload)
                if let d = try? MessageFramer.encode(msg) {
                    conn.send(content: d, completion: .contentProcessed({ _ in }))
                }
                self.receive()
            case .failed(let err):
                print("Verifier conn failed: \(err)")
            default: break
            }
        }
        conn.start(queue: .main)
    }

    private func receive() {
        guard let conn = conn else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64*1024) { [weak self] data, _, isEOF, error in
            guard let self = self else { return }
            if let data = data { self.buffer.append(data) }
            if var _ = self.conn, let msgs = try? MessageFramer.decode(stream: &self.buffer) {
                for m in msgs { self.handle(message: m) }
            }
            if isEOF || error != nil { self.conn?.cancel(); self.conn = nil; return }
            self.receive()
        }
    }

    private func handle(message: FramedMessage) {
        switch message.type {
        case .heartbeat:
            if let p = message.payload, let hb = try? JSONDecoder.lansync.decode(HeartbeatMsg.self, from: p) {
                latestEpoch = max(latestEpoch, hb.epoch)
                latestSeq = hb.latestSeq
                DiagnosticsModel.shared.epoch = hb.epoch
                DiagnosticsModel.shared.hostID = hb.hostID
                DiagnosticsModel.shared.latestSeq = hb.latestSeq
            }
        case .opBroadcast:
            if let p = message.payload, let op = try? JSONDecoder.lansync.decode(Op.self, from: p) {
                // Apply op via Replicator
                Task { @MainActor in
                    Replicator.shared.apply(op: op)
                }
            }
        default:
            break
        }
    }

    func propose(op: Op) {
        guard let conn = conn else { return }
        let payload = try? JSONEncoder.lansync.encode(op)
        let msg = FramedMessage(type: .opPropose, payload: payload)
        if let d = try? MessageFramer.encode(msg) {
            conn.send(content: d, completion: .contentProcessed({ _ in }))
        }
    }
}

