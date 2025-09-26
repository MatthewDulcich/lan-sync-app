import Foundation
import Combine

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import Network

final class PeerDiscovery: NSObject, ObservableObject {
    static let shared = PeerDiscovery()
    private override init() { super.init() }

    // Service types
    static let metaServiceType = "_lansyncmeta._tcp."
    static let blobServiceType = "_lansyncblob._tcp."

    private var browser: NetServiceBrowser?
    @Published var discoveredHosts: [NetService] = []

    func startBrowsing() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: Self.metaServiceType, inDomain: "local.")
    }

    func stopBrowsing() {
        browser?.stop()
        browser = nil
        discoveredHosts.removeAll()
    }

    // Host advertise
    private var metaService: NetService?
    private var blobService: NetService?

    func startAdvertising(name: String, metaPort: Int32, blobPort: Int32) {
        let meta = NetService(domain: "local.", type: Self.metaServiceType, name: name, port: metaPort)
        let blob = NetService(domain: "local.", type: Self.blobServiceType, name: name, port: blobPort)
        meta.publish()
        blob.publish()
        self.metaService = meta
        self.blobService = blob
    }

    func stopAdvertising() {
        metaService?.stop()
        blobService?.stop()
        metaService = nil
        blobService = nil
    }
}

extension PeerDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        discoveredHosts.append(service)
        service.resolve(withTimeout: 5.0)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        discoveredHosts.removeAll { $0 == service }
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        // Resolved; Host address is available from sender.addresses
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        // Handle resolution failure
    }
}
