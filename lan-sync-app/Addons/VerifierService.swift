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
        print("VerifierService: Attempting to connect to \(host):\(port)")
        print("VerifierService: DeviceID: \(deviceID), SessionID: \(sessionID), Epoch: \(epochSeen)")
        
        let conn = NWConnection(host: host, port: port, using: .tcp)
        self.conn = conn
        conn.stateUpdateHandler = { state in
            print("VerifierService: Connection state changed to \(state)")
            switch state {
            case .ready:
                print("VerifierService: Connection ready, sending hello message")
                let hello = HelloMsg(sessionID: sessionID, deviceID: deviceID, epochSeen: epochSeen, userDisplayName: userDisplayName)
                let payload = try? JSONEncoder.lansync.encode(hello)
                let msg = FramedMessage(type: .hello, payload: payload)
                if let d = try? MessageFramer.encode(msg) {
                    print("VerifierService: Sending hello message, size: \(d.count) bytes")
                    conn.send(content: d, completion: .contentProcessed({ error in
                        if let error = error {
                            print("VerifierService: Failed to send hello: \(error)")
                        } else {
                            print("VerifierService: Hello message sent successfully")
                        }
                    }))
                } else {
                    print("VerifierService: Failed to encode hello message")
                }
                self.receive()
            case .failed(let err):
                print("VerifierService: Connection failed with error: \(err)")
            case .preparing:
                print("VerifierService: Connection preparing...")
            case .setup:
                print("VerifierService: Connection setting up...")
            case .waiting(let error):
                print("VerifierService: Connection waiting: \(error)")
            case .cancelled:
                print("VerifierService: Connection cancelled")
            @unknown default:
                print("VerifierService: Unknown connection state: \(state)")
            }
        }
        conn.start(queue: .main)
        print("VerifierService: Connection start called")
    }

    private func receive() {
        guard let conn = conn else { 
            print("VerifierService: No connection available for receive")
            return 
        }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64*1024) { [weak self] data, _, isEOF, error in
            guard let self = self else { return }
            
            if let error = error {
                print("VerifierService: Receive error: \(error)")
            }
            
            if let data = data { 
                print("VerifierService: Received \(data.count) bytes")
                self.buffer.append(data)
                print("VerifierService: Buffer now contains \(self.buffer.count) bytes")
            }
            
            if var bufferCopy = self.conn != nil ? self.buffer : nil {
                do {
                    let msgs = try MessageFramer.decode(stream: &bufferCopy)
                    print("VerifierService: Decoded \(msgs.count) messages")
                    for m in msgs { self.handle(message: m) }
                    self.buffer = bufferCopy
                    print("VerifierService: Buffer updated to \(self.buffer.count) bytes after processing")
                } catch {
                    print("VerifierService: Failed to decode messages: \(error)")
                }
            }
            
            if isEOF {
                print("VerifierService: Connection ended (EOF)")
                self.conn?.cancel()
                self.conn = nil
                return
            }
            
            if error != nil { 
                print("VerifierService: Closing connection due to error")
                self.conn?.cancel()
                self.conn = nil
                return 
            }
            
            self.receive()
        }
    }

    private func handle(message: FramedMessage) {
        print("VerifierService: Handling message type: \(message.type)")
        switch message.type {
        case .heartbeat:
            if let p = message.payload, let hb = try? JSONDecoder.lansync.decode(HeartbeatMsg.self, from: p) {
                print("VerifierService: Received heartbeat - epoch: \(hb.epoch), seq: \(hb.latestSeq), host: \(hb.hostID)")
                latestEpoch = max(latestEpoch, hb.epoch)
                latestSeq = hb.latestSeq
                DiagnosticsModel.shared.epoch = hb.epoch
                DiagnosticsModel.shared.hostID = hb.hostID
                DiagnosticsModel.shared.latestSeq = hb.latestSeq
            } else {
                print("VerifierService: Failed to decode heartbeat message")
            }
        case .opBroadcast:
            if let p = message.payload, let op = try? JSONDecoder.lansync.decode(Op.self, from: p) {
                print("VerifierService: Received op broadcast - opId: \(op.opId), kind: \(op.kind)")
                // Apply op via Replicator
                Task { @MainActor in
                    Replicator.shared.apply(op: op)
                }
            } else {
                print("VerifierService: Failed to decode op broadcast message")
            }
        default:
            print("VerifierService: Unhandled message type: \(message.type)")
        }
    }

    func propose(op: Op) {
        guard let conn = conn else { 
            print("VerifierService: Cannot propose op - no connection available")
            return 
        }
        print("VerifierService: Proposing op - opId: \(op.opId), kind: \(op.kind)")
        let payload = try? JSONEncoder.lansync.encode(op)
        let msg = FramedMessage(type: .opPropose, payload: payload)
        if let d = try? MessageFramer.encode(msg) {
            print("VerifierService: Sending op proposal, size: \(d.count) bytes")
            conn.send(content: d, completion: .contentProcessed({ error in
                if let error = error {
                    print("VerifierService: Failed to send op proposal: \(error)")
                } else {
                    print("VerifierService: Op proposal sent successfully")
                }
            }))
        } else {
            print("VerifierService: Failed to encode op proposal")
        }
    }
}

