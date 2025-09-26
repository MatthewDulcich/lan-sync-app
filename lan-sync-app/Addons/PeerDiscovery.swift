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
        print("PeerDiscovery: Starting to browse for service type: \(Self.metaServiceType)")
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: Self.metaServiceType, inDomain: "local.")
        print("PeerDiscovery: Browse started")
    }

    func stopBrowsing() {
        print("PeerDiscovery: Stopping browse")
        browser?.stop()
        browser = nil
        discoveredHosts.removeAll()
        print("PeerDiscovery: Browse stopped, cleared \(discoveredHosts.count) discovered hosts")
    }

    // Host advertise
    private var metaService: NetService?
    private var blobService: NetService?

    func startAdvertising(name: String, metaPort: Int32, blobPort: Int32) {
        print("PeerDiscovery: Starting to advertise with name: \(name), metaPort: \(metaPort), blobPort: \(blobPort)")
        let meta = NetService(domain: "local.", type: Self.metaServiceType, name: name, port: metaPort)
        let blob = NetService(domain: "local.", type: Self.blobServiceType, name: name, port: blobPort)
        meta.delegate = self
        blob.delegate = self
        meta.publish()
        blob.publish()
        self.metaService = meta
        self.blobService = blob
        print("PeerDiscovery: Started advertising meta and blob services")
    }

    func stopAdvertising() {
        print("PeerDiscovery: Stopping advertising")
        metaService?.stop()
        blobService?.stop()
        metaService = nil
        blobService = nil
        print("PeerDiscovery: Stopped advertising")
    }
}

extension PeerDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("PeerDiscovery: Found service: \(service.name) of type \(service.type) in domain \(service.domain)")
        service.delegate = self
        discoveredHosts.append(service)
        service.resolve(withTimeout: 5.0)
        print("PeerDiscovery: Total discovered hosts: \(discoveredHosts.count), moreComing: \(moreComing)")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print("PeerDiscovery: Removed service: \(service.name)")
        let initialCount = discoveredHosts.count
        discoveredHosts.removeAll { $0 == service }
        print("PeerDiscovery: Removed service, hosts count: \(initialCount) -> \(discoveredHosts.count)")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        print("PeerDiscovery: Browser failed to search: \(errorDict)")
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        print("PeerDiscovery: Service resolved: \(sender.name) at \(sender.hostName ?? "unknown") port \(sender.port)")
        if let addresses = sender.addresses {
            print("PeerDiscovery: Service has \(addresses.count) addresses")
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("PeerDiscovery: Service failed to resolve: \(sender.name), error: \(errorDict)")
    }
    
    func netServiceDidPublish(_ sender: NetService) {
        print("PeerDiscovery: Service published successfully: \(sender.name) of type \(sender.type) on port \(sender.port)")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        print("PeerDiscovery: Service failed to publish: \(sender.name), error: \(errorDict)")
    }
}
