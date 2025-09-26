# LANSyncApp AI Coding Instructions

## Project Overview
This is an **offline-first local network sync system** for iOS/iPadOS + Mac Catalyst using SwiftUI + SwiftData. It implements an **Aggregator/Verifier topology** where one device acts as host, managing an append-only operation log (OpLog) and content-addressed blob storage with resumable transfers.

## Core Architecture Patterns

### 1. Operation-Based CRDT with Epoch-Ordered Consensus
- **Operations** (`Op` in `Ops.swift`) are the atomic units of change with fields: `epoch`, `seq`, `opId`, `authorDevice`, `time`, `kind`, `recordID`
- **Epochs** increment when hostship changes - peers only accept ops from the highest epoch
- **Host assigns sequence numbers** (`seq`) to accepted ops and broadcasts them to all peers
- **LWW (Last Writer Wins)** merging: fields merge by max `op.time` at host, with `authorDevice` as tiebreaker
- Use `SessionManager.shared.propose(op)` to submit operations - never manipulate SwiftData directly

### 2. Host/Verifier Network Topology
- **One Host per session**: runs `HostService` (metadata) and `BlobServer` (content) on different TCP ports
- **Multiple Verifiers**: connect via `VerifierService`, discover hosts via Bonjour (`PeerDiscovery`)
- **QR Join**: hosts generate QR codes with `{sessionID, host, port, secret, epoch}` for secure session joining
- **Manual hostship handover**: any peer can call `requestHostship()` to increment epoch and become new host

### 3. SwiftData Integration via Replicator
- **Never modify SwiftData directly** - all changes flow through `Replicator.shared.apply(op: Op)`
- **Context Injection**: `ContextBridge().hidden()` overlay in main view provides ModelContext to Replicator
- **Idempotency**: operations are deduplicated by `opId` to handle network retransmissions
- **Optimistic UI**: local ops are applied immediately before network confirmation

### 4. Content-Addressed Blob Storage
- **SHA256 hashing**: blobs stored by content hash in `BlobStore` with directory sharding (`/ab/cd/abcd...`)
- **Chunked transfers**: 64KB chunks with resumable byte-range requests via `BlobClient/BlobServer`
- **Reference via `blobHash`**: Unit model stores hash strings, not file paths
- **Store then reference**: `BlobStore.shared.store(data)` returns hash for Op attachment

### 5. Claim/Lease System for Optimistic Locking
- **First-writer-wins**: enforced by host op ordering, not distributed consensus
- **Auto-expiring leases**: `LeaseManager.shared.grant(recordID, owner, seconds)`
- **Claim workflow**: `SessionManager.claim(recordID)` → exclusive edit access → `unclaim(recordID)`

## Development Workflows

### Running the App
```bash
# Required: Mac with macOS 14+ for hosting (iOS devices can be verifiers)
# 1. Open lan-sync-app.xcodeproj in Xcode 15+
# 2. Select "My Mac (Designed for iPad)" scheme
# 3. Run → Tap "Become Host" 
# 4. Settings → Host QR → Scan from other devices via Settings → Join via QR
```

### Essential Info.plist Configuration
```xml
<!-- Required for iOS 14+ Bonjour and local networking -->
<key>NSLocalNetworkUsageDescription</key>
<string>This app needs local network access to sync data between devices</string>
<key>NSBonjourServices</key>
<array>
    <string>_lansyncmeta._tcp</string>
    <string>_lansyncblob._tcp</string>
</array>
```

### Critical Integration Points
- **Context Bridge**: `ContextBridge().hidden()` overlay in `ContentView` injects SwiftData ModelContext into `Replicator.shared`
- **Operation Creation**: Use `SessionManager.createUnit(initial: [String: FieldValue])` - never `context.insert()` directly
- **Service Names**: Bonjour services must match `PeerDiscovery.metaServiceType` and `PeerDiscovery.blobServiceType`
- **Port Timing**: `advertiseWhenReady()` polling prevents race conditions in service startup

### Message Flow Debugging
- **Diagnostics View**: shows epochs, sequence numbers, peer connections, throughput stats
- **Console patterns**: `HostService:`, `VerifierService:`, `Replicator:` prefixes indicate which layer logged
- **Frame inspection**: `MessageFramer` handles TCP message boundaries - check for truncation issues

## Key Implementation Patterns

### Creating New Op Types
```swift
// 1. Add to OpKind enum in Ops.swift
case myNewOperation

// 2. Handle in Replicator.swift apply() switch
case .myNewOperation:
    // Apply to SwiftData model, check existing record state
    
// 3. Add convenience method to SessionManager
func performMyOperation(recordID: UUID, value: SomeType) {
    let op = Op(epoch: epoch, seq: nil, opId: UUID(), 
                authorDevice: userDisplayName, time: Date(),
                kind: .myNewOperation, recordID: recordID, 
                fields: ["key": FieldValue.string(value)])
    propose(op)
}
```

### Network Service Extension
- **HostService**: handles incoming verifier connections, broadcasts ops to all peers
- **VerifierService**: connects to host, proposes local ops, receives broadcasts
- **Message types** in `MessageTypes.swift`: `hello`, `heartbeat`, `opPropose`, `opBroadcast`, etc.
- **Framing**: all TCP messages use `MessageFramer` for length-prefixed JSON payloads

### Security Layer (v1 Implementation)
- **QR-based session secrets**: `QRJoinCodec` encodes/decodes session join info
- **HMAC framework ready**: `HMACSecurity.swift` provides signing/verification (not yet enabled per-frame)
- **Future**: TLS with certificate pinning for production deployments

## File Organization Conventions
- **Root level**: Core SwiftUI views, models (`Unit.swift`), and orchestration (`SessionManager.swift`)
- **`Addons/`**: Drop-in networking and storage components - can be developed/tested independently
- **`UIExtras/`**: Secondary UI components (Settings, QR views) - not critical path
- **Singletons pattern**: `HostService.shared`, `SessionManager.shared`, etc. for app-wide state

## Common Debugging Scenarios
- **"No ops received"**: Check epoch alignment between host/verifier and Bonjour service discovery
- **"SwiftData not updating"**: Verify `ContextBridge` overlay exists and `Replicator.apply()` is called
- **"Blob transfer stuck"**: Check `BlobServer` port availability and chunk boundary handling
- **"Host handover failed"**: Ensure all peers see the new epoch before old host stops services