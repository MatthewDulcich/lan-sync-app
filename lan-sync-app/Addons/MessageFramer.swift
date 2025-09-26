import Foundation
import Network

final class MessageFramer {
    static func encode(_ message: FramedMessage) throws -> Data {
        let body = try JSONEncoder.lansync.encode(message)
        let len = UInt32(body.count).bigEndian
        
        // Safe way to encode UInt32 without potential alignment issues
        var framed = Data()
        framed.append(UInt8((len >> 24) & 0xFF))
        framed.append(UInt8((len >> 16) & 0xFF))
        framed.append(UInt8((len >> 8) & 0xFF))
        framed.append(UInt8(len & 0xFF))
        framed.append(body)
        return framed
    }

    static func decode(stream: inout Data) throws -> [FramedMessage] {
        var out: [FramedMessage] = []
        while stream.count >= 4 {
            // Safe way to read UInt32 from potentially misaligned data
            let lenBytes = Array(stream.prefix(4))
            let len = UInt32(bigEndian: UInt32(lenBytes[0]) << 24 | 
                                      UInt32(lenBytes[1]) << 16 | 
                                      UInt32(lenBytes[2]) << 8 | 
                                      UInt32(lenBytes[3]))
            
            print("MessageFramer: Stream size: \(stream.count), Message length: \(len)")
            
            // Bounds checking for message length
            guard len <= 1024 * 1024 else { // 1MB max message size
                print("MessageFramer: Message too large: \(len) bytes")
                throw NSError(domain: "MessageFramer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Message too large: \(len) bytes"])
            }
            
            guard stream.count >= 4 + Int(len) else { 
                print("MessageFramer: Incomplete message, need \(4 + Int(len)) bytes but have \(stream.count)")
                break 
            }
            
            // Safe range extraction with bounds checking
            let startIndex = 4
            let endIndex = startIndex + Int(len)
            print("MessageFramer: Extracting range \(startIndex)..<\(endIndex) from stream of size \(stream.count)")
            
            guard endIndex <= stream.count else {
                print("MessageFramer: Invalid range - endIndex \(endIndex) > stream.count \(stream.count)")
                throw NSError(domain: "MessageFramer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid message bounds"])
            }
            
            // Additional safety check for Range validity
            guard startIndex < endIndex && startIndex >= 0 && endIndex <= stream.count else {
                print("MessageFramer: Invalid range parameters - start: \(startIndex), end: \(endIndex), stream: \(stream.count)")
                throw NSError(domain: "MessageFramer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid range parameters"])
            }
            
            // Use safer Data extraction method to avoid Range issues
            let body = Data(stream.dropFirst(startIndex).prefix(Int(len)))
            print("MessageFramer: Extracted body of size \(body.count)")
            
            let msg = try JSONDecoder.lansync.decode(FramedMessage.self, from: body)
            out.append(msg)
            
            let bytesToRemove = 4 + Int(len)
            print("MessageFramer: Removing \(bytesToRemove) bytes from stream")
            stream.removeFirst(bytesToRemove)
            print("MessageFramer: Stream size after removal: \(stream.count)")
        }
        return out
    }
}
