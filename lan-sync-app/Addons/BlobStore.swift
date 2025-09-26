import Foundation
import CryptoKit

final class BlobStore {
    static let shared = BlobStore()

    private let fm = FileManager.default
    private let root: URL
    private init() {
        root = fm.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("images", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func path(for hash: String) -> URL { // hash is hex string
        let a = String(hash.prefix(2))
        let b = String(hash.dropFirst(2).prefix(2))
        let dir = root.appendingPathComponent(a, isDirectory: true).appendingPathComponent(b, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(hash)
    }

    func store(data: Data) -> String {
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        let url = path(for: hash)
        if !fm.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        return hash
    }

    func exists(hash: String) -> Bool { fm.fileExists(atPath: path(for: hash).path) }

    func size(hash: String) -> Int64? {
        let url = path(for: hash)
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let s = attrs[.size] as? NSNumber {
            return s.int64Value
        }
        return nil
    }

    func readRange(hash: String, offset: Int64, length: Int) -> Data? {
        let url = path(for: hash)
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        do {
            try fh.seek(toOffset: UInt64(offset))
            return try fh.read(upToCount: length)
        } catch { return nil }
    }
}
