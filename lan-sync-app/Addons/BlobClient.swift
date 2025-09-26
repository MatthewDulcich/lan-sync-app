import Foundation
import Network

final class BlobClient {
    static let shared = BlobClient()
    private init() {}

    func fetch(host: NWEndpoint.Host, port: NWEndpoint.Port, hash: String, to url: URL,
               resumeFrom: Int64 = 0, totalSize: Int64? = nil,
               progress: @escaping (Int64) -> Void,
               completion: @escaping (Result<Void, Error>) -> Void) {

        let conn = NWConnection(host: host, port: port, using: .tcp)
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.requestNext(conn: conn, hash: hash, to: url, offset: resumeFrom, progress: progress, completion: completion)
            case .failed(let err):
                completion(.failure(err))
            default: break
            }
        }
        conn.start(queue: .global())
    }

    private func requestNext(conn: NWConnection, hash: String, to url: URL, offset: Int64,
                             progress: @escaping (Int64) -> Void,
                             completion: @escaping (Result<Void, Error>) -> Void) {
        // Stream whole file in chunks of 64k for demo; resumable by re-calling with new offset.
        let chunkSize = 64 * 1024
        let line = "GET \(hash) \(offset) \(chunkSize)\n"
        conn.send(content: line.data(using: .utf8), completion: .contentProcessed { _ in
            conn.receive(minimumIncompleteLength: 1, maximumLength: chunkSize) { data, _, isEOF, error in
                if let error = error { completion(.failure(error)); conn.cancel(); return }
                guard let data = data else { completion(.success(())); conn.cancel(); return }
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        let fh = try FileHandle(forWritingTo: url)
                        try fh.seekToEnd()
                        try fh.write(contentsOf: data)
                        try fh.close()
                    } else {
                        try data.write(to: url)
                    }
                } catch {
                    completion(.failure(error)); conn.cancel(); return
                }
                let newOffset = offset + Int64(data.count)
                progress(newOffset)
                if data.count < chunkSize || isEOF {
                    completion(.success(())); conn.cancel(); return
                } else {
                    self.requestNext(conn: conn, hash: hash, to: url, offset: newOffset, progress: progress, completion: completion)
                }
            }
        })
    }
}
