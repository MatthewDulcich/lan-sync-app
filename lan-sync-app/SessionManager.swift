// SessionManager.swift (updated) — wires HostService/VerifierService/BlobServer/PeerDiscovery
// and routes ops through the network. Drop this in to replace your existing file.

import Foundation
import SwiftUI
import SwiftData
import Network

@MainActor
final class SessionManager: ObservableObject {
    // MARK: - Public state
    @Published var sessionID: String?
    @Published var epoch: UInt64 = 0
    @Published var currentHostID: String?
    @Published var isHost: Bool = false

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
    static var shared: SessionManager!

    override init() {
        super.init()
        SessionManager.shared = self
    }

    // MARK: - Hosting

    func startHosting() {
        if sessionID == nil { sessionID = UUID().uuidString }
        setGlobalSessionID(sessionID!)
        epoch &+= 1
        isHost = true
        currentHostID = userDisplayName
        DiagnosticsModel.shared.isHost = true
        DiagnosticsModel.shared.sessionID = sessionID!
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
        if let mp = metaPort?.rawValue, let bp = blobPort?.rawValue {
            PeerDiscovery.shared.startAdvertising(name: currentHostID ?? "Host", metaPort: Int32(mp), blobPort: Int32(bp))
        }
    }

    // MARK: - Join via QR (or programmatically)

    func joinViaQR() {
        // Placeholder: try to decode a Base64 JSON from clipboard (developer convenience)
        #if canImport(UIKit)
        if let s = UIPasteboard.general.string, let info = QRJoinCodec.decode(s) {
            join(with: info)
            return
        }
        #endif
        // Fallback: demo defaults (adjust as needed)
        print("joinViaQR(): No QR in clipboard; please call join(with:) after scanning.")
    }

    func join(with info: SessionJoinInfo) {
        self.sessionID = info.sessionID
        setGlobalSessionID(info.sessionID)
        self.isHost = false
        self.currentHostID = "Host@\(info.host)"
        self.epoch = max(self.epoch, info.epoch)
        DiagnosticsModel.shared.isHost = false
        DiagnosticsModel.shared.sessionID = info.sessionID
        DiagnosticsModel.shared.epoch = self.epoch
        DiagnosticsModel.shared.hostID = self.currentHostID ?? ""

        let host = NWEndpoint.Host(info.host)
        guard let port = NWEndpoint.Port(rawValue: info.port) else { return }
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
        if let mp = metaPort?.rawValue, let bp = blobPort?.rawValue {
            PeerDiscovery.shared.startAdvertising(name: currentHostID ?? "Host", metaPort: Int32(mp), blobPort: Int32(bp))
        }
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
            let host = NWEndpoint.Host.ipv4(IPv4Address("127.0.0.1")!)
            let tempVS = VerifierService()
            tempVS.connect(host: host,
                           port: port,
                           deviceID: deviceID,
                           userDisplayName: userDisplayName,
                           sessionID: sessionID ?? "UNSET",
                           epochSeen: epoch)
            // After ready, send proposal (slight delay to give connection time)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                tempVS.propose(op: op)
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
    static func macHostName() -> String { Host.current().localizedName ?? "Mac" }
}
#endif

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Global SessionID bridge used by HostService heartbeats

extension SessionManager {
    static var globalSessionID: String?
    func setGlobalSessionID(_ s: String) { SessionManager.globalSessionID = s }
    static var sharedSessionID: String { SessionManager.globalSessionID ?? "UNSET" }
}
