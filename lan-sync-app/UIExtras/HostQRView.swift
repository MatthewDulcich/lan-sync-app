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
        guard session.isHost else { error = "Not hosting. Tap 'Become Host' first."; return }
        guard let sessionID = session.sessionID else { error = "Missing Session ID"; return }
        
        // Debug: Check if HostService was even attempted to start
        print("HostQRView: Checking HostService port...")
        print("HostQRView: HostService.shared.port = \(String(describing: HostService.shared.port))")
        
        // Wait briefly for HostService port if not ready yet
        guard let metaPort = HostService.shared.port?.rawValue else {
            print("HostQRView: waiting for HostService port...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.prepareQR()
            }
            return
        }
        print("HostQRView: HostService port ready: \(metaPort)")
        
        guard let hostIP = NetworkInterfaces.primaryIPv4() else { 
            error = "No LAN IPv4 found. Check network connection."
            print("HostQRView: Failed to find LAN IPv4 address")
            return 
        }
        print("HostQRView: Found LAN IP: \(hostIP)")

        let secret = SessionSecretProvider.ensureSessionSecret()
        let info = SessionJoinInfo(sessionID: sessionID,
                                   host: hostIP,
                                   port: UInt16(metaPort),
                                   secret: secret,
                                   epoch: session.epoch)
        joinString = QRJoinCodec.encode(info)
        print("HostQRView: QR generated successfully")
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
        return getAddress(prefer:"en0") ?? getAddress(prefer:"eth0") ?? getNonLoopbackAddress()
        #else
        return getNonLoopbackAddress() ?? getAddress(prefer:"en0") ?? getAddress(prefer:"eth0")
        #endif
    }
    
    private static func getNonLoopbackAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            
            let name = String(cString: interface.ifa_name)
            guard let addr = interface.ifa_addr else { continue }
            let addrFamily = addr.pointee.sa_family
            
            // Skip loopback and non-IPv4 interfaces
            guard addrFamily == UInt8(AF_INET) else { continue }
            guard !name.starts(with: "lo") else { continue }
            
            // Use getnameinfo for safe IP address conversion
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, socklen_t(0), NI_NUMERICHOST)
            
            if result == 0 {
                let ipString = String(cString: hostname)
                // Skip localhost and APIPA addresses
                if !ipString.starts(with: "127.") && !ipString.starts(with: "169.254.") {
                    print("Found LAN IP: \(ipString) on interface: \(name)")
                    address = ipString
                    break
                }
            }
        }
        return address
    }

    private static func getAddress(prefer: String?) -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            
            let name = String(cString: interface.ifa_name)
            if let prefer, name != prefer { continue }
            
            guard let addr = interface.ifa_addr else { continue }
            let addrFamily = addr.pointee.sa_family
            
            // Only handle IPv4
            guard addrFamily == UInt8(AF_INET) else { continue }
            
            // Use getnameinfo for safe IP address conversion
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, socklen_t(0), NI_NUMERICHOST)
            
            if result == 0 {
                address = String(cString: hostname)
                break
            }
        }
        return address
    }
}
