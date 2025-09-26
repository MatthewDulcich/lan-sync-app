import Foundation
import Combine
import Network
import SwiftUI

final class HostService: ObservableObject {
    static let shared = HostService()
    private init() {}

    private var listener: NWListener?
    private(set) var port: NWEndpoint.Port?
    private var conns: [NWConnection] = []
    private var buffer: [ObjectIdentifier: Data] = [:]

    @Published var epoch: UInt64 = 0
    @Published var hostID: String = UUID().uuidString

    private var heartbeatTimer: Timer?

    func start(epoch: UInt64) throws -> UInt16 {
        self.epoch = epoch
        print("HostService: Starting with epoch \(epoch)")
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: .any)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.setup(conn)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            print("HostService: Listener state changed to \(state)")
            if case .ready = state { 
                self?.port = self?.listener?.port 
                print("HostService: Port ready: \(self?.port?.rawValue ?? 0)")
            }
            if case .failed(let error) = state {
                print("HostService: Listener failed with error: \(error)")
            }
        }
        listener?.start(queue: .main)
        print("HostService: Listener started, initial port: \(listener?.port?.rawValue ?? 0)")

        // Heartbeats
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.broadcastHeartbeat()
        }

        return UInt16(listener?.port?.rawValue ?? 0)
    }

    func stop() {
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        listener?.cancel(); listener = nil; port = nil
        conns.forEach { $0.cancel() }
        conns.removeAll(); buffer.removeAll()
    }

    private func setup(_ conn: NWConnection) {
        print("HostService: Setting up new connection from client")
        conns.append(conn)
        buffer[ObjectIdentifier(conn)] = Data()
        conn.stateUpdateHandler = { [weak self] state in
            print("HostService: Client connection state changed to \(state)")
            if case .failed(let error) = state { 
                print("HostService: Client connection failed: \(error)")
                conn.cancel() 
            }
            if case .ready = state {
                print("HostService: Client connection ready")
            }
        }
        conn.start(queue: .main)
        receive(on: conn)
        print("HostService: Total active connections: \(conns.count)")
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64*1024) { [weak self] data, _, isEOF, error in
            guard let self = self else { return }
            let key = ObjectIdentifier(conn)
            if var buf = self.buffer[key] {
                if let data = data { buf.append(data) }
                if let msgs = try? MessageFramer.decode(stream: &buf) {
                    for m in msgs { self.handle(message: m, from: conn) }
                }
                self.buffer[key] = buf
            }
            if isEOF || error != nil { conn.cancel(); return }
            self.receive(on: conn)
        }
    }

    private func handle(message: FramedMessage, from conn: NWConnection) {
        print("HostService: Received message type: \(message.type) from client")
        switch message.type {
        case .hello:
            print("HostService: Received hello from client")
            return
        case .opPropose:
            guard let data = message.payload, var op = try? JSONDecoder.lansync.decode(Op.self, from: data) else { 
                print("HostService: Failed to decode op proposal")
                return 
            }
            print("HostService: Received op proposal: \(op.opId)")
            // assign seq
            let seq = (try? OpLogStore.shared.assignSeqAndAppend(&op, epoch: epoch)) ?? (op.seq ?? 0)
            DiagnosticsModel.shared.latestSeq = seq
            // broadcast
            let payload = try? JSONEncoder.lansync.encode(op)
            let msg = FramedMessage(type: .opBroadcast, payload: payload)
            if let d = try? MessageFramer.encode(msg) {
                print("HostService: Broadcasting op to \(conns.count) clients")
                for c in conns { c.send(content: d, completion: .contentProcessed({ _ in })) }
            }
        default:
            print("HostService: Unhandled message type: \(message.type)")
            return
        }
    }

    private func broadcastHeartbeat() {
        let hb = HeartbeatMsg(sessionID: SessionManager.sharedSessionID,
                              epoch: epoch,
                              hostID: hostID,
                              latestSeq: OpLogStore.shared.latestSeq,
                              time: Date())
        let payload = try? JSONEncoder.lansync.encode(hb)
        let msg = FramedMessage(type: .heartbeat, payload: payload)
        guard let d = try? MessageFramer.encode(msg) else { return }
        print("HostService: Broadcasting heartbeat to \(conns.count) clients")
        for c in conns { c.send(content: d, completion: .contentProcessed({ _ in })) }
    }
}

