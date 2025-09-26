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
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: .any)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.setup(conn)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.port = self?.listener?.port }
        }
        listener?.start(queue: .main)

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
        conns.append(conn)
        buffer[ObjectIdentifier(conn)] = Data()
        conn.stateUpdateHandler = { state in
            if case .failed = state { conn.cancel() }
        }
        conn.start(queue: .main)
        receive(on: conn)
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
        switch message.type {
        case .hello:
            // accept
            return
        case .opPropose:
            guard let data = message.payload, var op = try? JSONDecoder.lansync.decode(Op.self, from: data) else { return }
            // assign seq
            let seq = (try? OpLogStore.shared.assignSeqAndAppend(&op, epoch: epoch)) ?? (op.seq ?? 0)
            DiagnosticsModel.shared.latestSeq = seq
            // broadcast
            let payload = try? JSONEncoder.lansync.encode(op)
            let msg = FramedMessage(type: .opBroadcast, payload: payload)
            if let d = try? MessageFramer.encode(msg) {
                for c in conns { c.send(content: d, completion: .contentProcessed({ _ in })) }
            }
        default:
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
        for c in conns { c.send(content: d, completion: .contentProcessed({ _ in })) }
    }
}

