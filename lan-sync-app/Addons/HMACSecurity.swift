import Foundation
import CryptoKit

struct HMACSecurity {
    let sessionSecret: Data

    init(sessionSecret: Data) { self.sessionSecret = sessionSecret }

    func sign(nonce: Data, data: Data) -> Data {
        let key = SymmetricKey(data: sessionSecret)
        let mac = HMAC<SHA256>.authenticationCode(for: nonce + data, using: key)
        return Data(mac)
    }

    func verify(nonce: Data, data: Data, signature: Data) -> Bool {
        let key = SymmetricKey(data: sessionSecret)
        do {
            return try HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: nonce + data, using: key)
        } catch {
            return false
        }
    }
}
