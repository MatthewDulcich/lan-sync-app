import Foundation
import Network

final class BlobServer {
    static let shared = BlobServer()

    private var listener: NWListener?
    private(set) var port: NWEndpoint.Port?

    func start(on port: UInt16 = 0) throws -> UInt16 {
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handle(conn: conn)
        }
        listener?.start(queue: .main)
        listener?.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.port = self?.listener?.port
            }
        }
        return UInt16(listener?.port?.rawValue ?? 0)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func handle(conn: NWConnection) {
        conn.start(queue: .main)
        receiveNext(on: conn, buffer: Data())
    }

    private func receiveNext(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isEOF, error in
            var buf = buffer
            if let data = data { buf.append(data) }
            if isEOF || error != nil { conn.cancel(); return }
            self?.process(on: conn, buffer: &buf)
            self?.receiveNext(on: conn, buffer: buf)
        }
    }

    private func process(on conn: NWConnection, buffer: inout Data) {
        // Protocol: ASCII line "GET <hash> <offset> <length>\n"
        while let range = buffer.firstRange(of: Data([0x0a])) { // newline
            let lineData = buffer.prefix(upTo: range.lowerBound)
            buffer.removeSubrange(..<range.upperBound)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            let parts = line.split(separator: " ")
            guard parts.count == 4, parts[0] == "GET" else { continue }
            let hash = String(parts[1])
            guard let offset = Int64(parts[2]), let length = Int(parts[3]) else { continue }
            if let chunk = BlobStore.shared.readRange(hash: hash, offset: offset, length: length) {
                conn.send(content: chunk, completion: .contentProcessed({ _ in }))
            } else {
                conn.send(content: Data(), completion: .contentProcessed({ _ in }))
            }
        }
    }
}
