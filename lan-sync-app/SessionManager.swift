// SessionManager.swift (updated) — wires HostService/VerifierService/BlobServer/PeerDiscovery
// and routes ops through the network. Drop this in to replace your existing file.

import Foundation
import SwiftUI
import SwiftData
import Network
import Combine

@MainActor
final class SessionManager: ObservableObject {
    // MARK: - Public state
    @Published var sessionID: String?
    @Published var epoch: UInt64 = 0
    @Published var currentHostID: String?
    @Published var isHost: Bool = false
    @Published var lastError: String?

    // MARK: - Identity
    let deviceID: String = String(UUID().uuidString.prefix(6))
    @Published var personName: String = UserDefaults.standard.string(forKey: "PersonName") ?? "User"
    var userDisplayName: String {
        return "\(personName)@\(Host.currentName)"
    }

    // MARK: - Services
    let prefetcher = Prefetcher.shared

    // host endpoints
    private var metaPort: NWEndpoint.Port?
    private var blobPort: NWEndpoint.Port?

    // Singleton handle for other layers (e.g., Replicator.enqueueLocal uses this)
    static var shared: SessionManager? = nil

    init() {
        SessionManager.shared = self
        validatePlistConfiguration()
    }

    // MARK: - Hosting

    func startHosting() {
        if sessionID == nil { sessionID = UUID().uuidString }
        guard let sessionID = sessionID else {
            print("SessionManager: Failed to create sessionID")
            return
        }
        SessionManager.globalSessionID = sessionID
        epoch &+= 1
        isHost = true
        currentHostID = userDisplayName
        DiagnosticsModel.shared.isHost = true
        DiagnosticsModel.shared.sessionID = sessionID
        DiagnosticsModel.shared.epoch = epoch
        DiagnosticsModel.shared.hostID = currentHostID ?? ""

        // Start metadata listener (HostService) and blob server
        do {
            let m = try HostService.shared.start(epoch: epoch)
            self.metaPort = NWEndpoint.Port(rawValue: UInt16(m))
        } catch {
            print("HostService start failed: \(error)")
        }
        do {
            let b = try BlobServer.shared.start()
            self.blobPort = NWEndpoint.Port(rawValue: UInt16(b))
        } catch {
            print("BlobServer start failed: \(error)")
        }

        // Advertise via Bonjour
        advertiseWhenReady()
    }

    // MARK: - Join via QR (or programmatically)

    func joinViaQR() {
        // Clear any previous error
        lastError = nil
        
        // Placeholder: try to decode a Base64 JSON from clipboard (developer convenience)
        #if canImport(UIKit)
        do {
            if let s = UIPasteboard.general.string, let info = QRJoinCodec.decode(s) {
                join(with: info)
                return
            }
        } catch {
            print("joinViaQR(): Clipboard access error: \(error)")
        }
        #endif
        // Provide user feedback for missing QR
        lastError = "No QR code found in clipboard. Please use Settings → Join via QR to scan a QR code, or copy a QR code to clipboard first."
        print("joinViaQR(): No QR in clipboard; please use proper QR scanner or copy QR to clipboard.")
    }

    func join(with info: SessionJoinInfo) {
        print("SessionManager: Attempting to join session")
        print("SessionManager: SessionID: \(info.sessionID)")
        print("SessionManager: Host: \(info.host):\(info.port)")
        print("SessionManager: Epoch: \(info.epoch)")
        
        self.sessionID = info.sessionID
        SessionManager.globalSessionID = info.sessionID
        self.isHost = false
        self.currentHostID = "Host@\(info.host)"
        self.epoch = max(self.epoch, info.epoch)
        DiagnosticsModel.shared.isHost = false
        DiagnosticsModel.shared.sessionID = info.sessionID
        DiagnosticsModel.shared.epoch = self.epoch
        DiagnosticsModel.shared.hostID = self.currentHostID ?? ""

        let host = NWEndpoint.Host(info.host)
        guard let port = NWEndpoint.Port(rawValue: info.port) else { 
            print("SessionManager: Invalid port: \(info.port)")
            return 
        }
        
        print("SessionManager: Starting VerifierService connection...")
        VerifierService.shared.connect(host: host,
                                       port: port,
                                       deviceID: deviceID,
                                       userDisplayName: userDisplayName,
                                       sessionID: info.sessionID,
                                       epochSeen: self.epoch)
    }

    // MARK: - Manual hostship takeover

    func requestHostship() {
        // Manual handover: become host locally (epoch+1), start listeners, advertise.
        epoch &+= 1
        isHost = true
        currentHostID = userDisplayName
        DiagnosticsModel.shared.isHost = true
        DiagnosticsModel.shared.epoch = epoch
        DiagnosticsModel.shared.hostID = currentHostID ?? ""

        do {
            let m = try HostService.shared.start(epoch: epoch)
            self.metaPort = NWEndpoint.Port(rawValue: UInt16(m))
        } catch {
            print("HostService start failed: \(error)")
        }
        do {
            let b = try BlobServer.shared.start()
            self.blobPort = NWEndpoint.Port(rawValue: UInt16(b))
        } catch {
            print("BlobServer start failed: \(error)")
        }
        advertiseWhenReady()
    }

    // MARK: - Proposing Ops

    func propose(_ op: Op) {
        var op = op
        op.epoch = epoch
        // Optimistic local apply for snappy UI
        Replicator.shared.apply(op: op)

        if isHost {
            // Loopback propose to HostService so peers get the broadcast
            guard let port = HostService.shared.port else { return }
            guard let ipv4 = IPv4Address("127.0.0.1") else {
                print("SessionManager: Failed to create localhost address")
                return
            }
            let host = NWEndpoint.Host.ipv4(ipv4)
            let vs = VerifierService.shared
            vs.connect(host: host,
                       port: port,
                       deviceID: deviceID,
                       userDisplayName: userDisplayName,
                       sessionID: sessionID ?? "UNSET",
                       epochSeen: epoch)
            // After ready, send proposal (slight delay to give connection time)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                vs.propose(op: op)
            }
        } else {
            VerifierService.shared.propose(op: op)
        }
    }

    // MARK: - High-level convenience API called by Views

    func claim(recordID: UUID, leaseSeconds: TimeInterval = 300) {
        var op = Op(epoch: epoch, seq: nil, opId: UUID(), authorDevice: userDisplayName, time: Date(),
                    kind: .claim, recordID: recordID, fields: nil, boolValue: nil, blobHash: nil, claimOwner: userDisplayName)
        propose(op)
        // locally grant lease (host will also enforce by op ordering)
        LeaseManager.shared.grant(recordID: recordID, owner: userDisplayName, seconds: leaseSeconds)
    }

    func unclaim(recordID: UUID) {
        let op = Op(epoch: epoch, seq: nil, opId: UUID(), authorDevice: userDisplayName, time: Date(),
                    kind: .unclaim, recordID: recordID)
        LeaseManager.shared.revoke(recordID: recordID)
        propose(op)
    }

    func setVerified(recordID: UUID, value: Bool) {
        let op = Op(epoch: epoch, seq: nil, opId: UUID(), authorDevice: userDisplayName, time: Date(),
                    kind: .verifySet, recordID: recordID, fields: nil, boolValue: value)
        propose(op)
    }

    func setChallenged(recordID: UUID, value: Bool) {
        let op = Op(epoch: epoch, seq: nil, opId: UUID(), authorDevice: userDisplayName, time: Date(),
                    kind: .challengeSet, recordID: recordID, fields: nil, boolValue: value)
        propose(op)
    }

    func setIllegible(recordID: UUID, value: Bool) {
        let op = Op(epoch: epoch, seq: nil, opId: UUID(), authorDevice: userDisplayName, time: Date(),
                    kind: .illegibleSet, recordID: recordID, fields: nil, boolValue: value)
        propose(op)
    }

    func editFields(recordID: UUID, changes: [String: FieldValue]) {
        let op = Op(epoch: epoch, seq: nil, opId: UUID(), authorDevice: userDisplayName, time: Date(),
                    kind: .editFields, recordID: recordID, fields: changes)
        propose(op)
    }

    func attachImage(recordID: UUID, blobHash: String) {
        let op = Op(epoch: epoch, seq: nil, opId: UUID(), authorDevice: userDisplayName, time: Date(),
                    kind: .attachImage, recordID: recordID, fields: nil, boolValue: nil, blobHash: blobHash)
        propose(op)
    }

    func createUnit(initial: [String: FieldValue]) {
        let rid = UUID()
        let op = Op(epoch: epoch, seq: nil, opId: UUID(), authorDevice: userDisplayName, time: Date(),
                    kind: .createUnit, recordID: rid, fields: initial)
        propose(op)
    }

    func deleteUnit(recordID: UUID) {
        let op = Op(epoch: epoch, seq: nil, opId: UUID(), authorDevice: userDisplayName, time: Date(),
                    kind: .deleteUnit, recordID: recordID)
        propose(op)
    }
    
    // Wait for HostService/BlobServer ports to be ready before advertising via Bonjour
    private func advertiseWhenReady(retries: Int = 50) { // ~10s at 0.2s intervals
        if let mp = HostService.shared.port?.rawValue, let bp = BlobServer.shared.port?.rawValue {
            self.metaPort = HostService.shared.port
            self.blobPort = BlobServer.shared.port
            PeerDiscovery.shared.startAdvertising(name: currentHostID ?? "Host", metaPort: Int32(mp), blobPort: Int32(bp))
            return
        }
        guard retries > 0 else {
            print("SessionManager: ports not ready; advertising skipped")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.advertiseWhenReady(retries: retries - 1)
        }
    }

    // MARK: - Runtime validation for required permissions
    private func validatePlistConfiguration() {
        #if os(iOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
        let info = Bundle.main.infoDictionary ?? [:]
        if info["NSLocalNetworkUsageDescription"] == nil {
            print("[Config] Missing NSLocalNetworkUsageDescription in Info.plist. Local Network permission prompt will not appear.")
            print("[Config] Add this to your target's Info tab: NSLocalNetworkUsageDescription = 'This app needs local network access to sync data between devices'")
        }
        if let services = info["NSBonjourServices"] as? [String] {
            let expected = [PeerDiscovery.metaServiceType, PeerDiscovery.blobServiceType]
            for s in expected where !services.contains(s) {
                print("[Config] NSBonjourServices is missing service type: \(s)")
                print("[Config] Add these to NSBonjourServices array: _lansyncmeta._tcp, _lansyncblob._tcp")
            }
        } else {
            print("[Config] Missing NSBonjourServices array in Info.plist. Bonjour advertise/browse may be blocked on iOS 14+.")
            print("[Config] SOLUTION: In Xcode, go to your target's Info tab and add NSBonjourServices array with: _lansyncmeta._tcp, _lansyncblob._tcp")
        }
        #endif
        #if os(macOS) && !targetEnvironment(macCatalyst)
        // Note: For sandboxed macOS apps, enable App Sandbox with network client/server entitlements.
        print("[Config] macOS: Ensure App Sandbox is enabled with com.apple.security.network.client and .server in the target entitlements.")
        #endif
    }
}

// MARK: - Host name helpers

enum Host {
    static var currentName: String {
        #if canImport(AppKit)
        return HostNameProvider.macHostName()
        #else
        return UIDevice.current.name
        #endif
    }
}

#if canImport(AppKit)
import AppKit
enum HostNameProvider {
    static func macHostName() -> String { Foundation.Host.current().localizedName ?? "Mac" }
}
#endif

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Global SessionID bridge used by HostService heartbeats

extension SessionManager {
    static var globalSessionID: String?
    static var sharedSessionID: String { SessionManager.globalSessionID ?? "UNSET" }
}

