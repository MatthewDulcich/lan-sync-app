import SwiftUI
import Network

struct HostQRView: View {
    @EnvironmentObject var session: SessionManager

    @State private var joinString: String = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            if let err = error {
                Text(err).foregroundStyle(.red)
            } else if !joinString.isEmpty {
                QRCodeView(text: joinString)
                    .frame(maxWidth: 320, maxHeight: 320)
                Text("Scan to join").font(.headline)
                ScrollView {
                    Text(joinString).font(.footnote).textSelection(.enabled)
                }.frame(maxHeight: 120)
            } else {
                ProgressView("Preparing QR…")
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Host QR")
        .onAppear(perform: prepareQR)
    }

    private func prepareQR() {
        guard session.isHost else { error = "Not hosting. Tap ‘Become Host’ first."; return }
        guard let sessionID = session.sessionID else { error = "Missing Session ID"; return }
        guard let metaPort = HostService.shared.port?.rawValue else { error = "Host metadata port not ready"; return }
        guard let hostIP = NetworkInterfaces.primaryIPv4() else { error = "No LAN IPv4 found"; return }

        let secret = SessionSecretProvider.ensureSessionSecret()
        let info = SessionJoinInfo(sessionID: sessionID,
                                   host: hostIP,
                                   port: UInt16(metaPort),
                                   secret: secret,
                                   epoch: session.epoch)
        joinString = QRJoinCodec.encode(info)
    }
}

// Session secret helper
enum SessionSecretProvider {
    static func ensureSessionSecret() -> String {
        let key = "SessionSecret"
        if let s = UserDefaults.standard.string(forKey: key) { return s }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        let b64 = data.base64EncodedString()
        UserDefaults.standard.set(b64, forKey: key)
        return b64
    }
}

// LAN IP helper
enum NetworkInterfaces {
    static func primaryIPv4() -> String? {
        #if os(iOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
        return getAddress(prefer:"en0") ?? getAddress(prefer:"eth0") ?? getAddress(prefer:nil)
        #else
        return getAddress(prefer:nil)
        #endif
    }

    private static func getAddress(prefer: String?) -> String? {
        var address : String?
        var ifaddr : UnsafeMutablePointer<ifaddrs>? = nil
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                let name = String(cString: interface.ifa_name)
                if let prefer, name != prefer { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) { // IPv4
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if (getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST) == 0) {
                        address = String(cString: hostname)
                        break
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
}