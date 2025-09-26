import Foundation
import CoreImage.CIFilterBuiltins
import SwiftUI

struct SessionJoinInfo: Codable {
    var sessionID: String
    var host: String // hostname or IP
    var port: UInt16 // metadata port
    var secret: String // base64 secret for HMAC
    var epoch: UInt64
}

enum QRJoinCodec {
    static func encode(_ info: SessionJoinInfo) -> String {
        let data = try! JSONEncoder.lansync.encode(info)
        return data.base64EncodedString()
    }
    static func decode(_ str: String) -> SessionJoinInfo? {
        guard let data = Data(base64Encoded: str) else { return nil }
        return try? JSONDecoder.lansync.decode(SessionJoinInfo.self, from: data)
    }
}

struct QRCodeView: View {
    let text: String
    var body: some View {
        if let img = makeQR(text: text) {
            Image(decorative: img, scale: 1, orientation: .up).interpolation(.none).resizable().scaledToFit()
        } else {
            Text("QR generation failed")
        }
    }
    func makeQR(text: String) -> CGImage? {
        let f = CIFilter.qrCodeGenerator()
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        guard let out = f.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let ctx = CIContext()
        return ctx.createCGImage(scaled, from: scaled.extent)
    }
}
