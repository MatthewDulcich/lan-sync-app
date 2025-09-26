import Foundation
import Network

final class MessageFramer {
    static func encode(_ message: FramedMessage) throws -> Data {
        let body = try JSONEncoder.lansync.encode(message)
        var len = UInt32(body.count).bigEndian
        var framed = Data(bytes: &len, count: 4)
        framed.append(body)
        return framed
    }

    static func decode(stream: inout Data) throws -> [FramedMessage] {
        var out: [FramedMessage] = []
        while stream.count >= 4 {
            let lenData = stream.prefix(4)
            let len = lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard stream.count >= 4 + Int(len) else { break }
            let body = stream.subdata(in: 4..<(4+Int(len)))
            let msg = try JSONDecoder.lansync.decode(FramedMessage.self, from: body)
            out.append(msg)
            stream.removeFirst(4 + Int(len))
        }
        return out
    }
}
