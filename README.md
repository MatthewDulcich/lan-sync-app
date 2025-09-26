# LANSyncApp — Aggregator/Verifier LAN Sync (Starter Project)

This project scaffolds an offline-first **local network sync** system for iOS/iPadOS + **Mac Catalyst**.
It uses **SwiftUI + SwiftData**, **Bonjour + Network.framework**, an append-only **OpLog**, and
**content-addressed blobs** with **resumable** transfers. Security v1 uses a session QR with a shared secret.

## Key Features
- **Aggregator/Verifier topology** with manual hostship handover (Epoch bump).
- **SwiftData** local store with **LWW** merges and **claim/lease** semantics.
- **Bonjour** discovery + TCP framed messages for metadata.
- **Content-addressed image store** (sha256), chunked + resumable pulls.
- **Diagnostics** panel for peers, epochs, seq, throughput, prefetch stats.

## Targets & Requirements
- Xcode 15+
- iOS 17+ / iPadOS 17+
- **Mac Catalyst** (macOS 14+ recommended) for hosting

## Structure
```
LANSyncApp/
  LANSyncAppApp.swift        // @main
  Models: Unit.swift
  Ops: FieldValue.swift, Ops.swift
  Views: RootView.swift, ContentListView.swift, UnitDetailView.swift, DiagnosticsView.swift
  Services: SessionManager.swift, Replicator.swift
  Addons/: (Networking, OpLog, BlobStore/Client/Server, QR encoding, HMAC, etc.)
  UIExtras/: SettingsView.swift, HostQRView.swift, JoinView.swift, QRScannerView.swift
```

## Getting Started
1. **Open** `LANSyncApp.xcodeproj` in Xcode.
2. In **RootView**, ensure the context bridge is present:
   ```swift
   VStack { /* ... */ }
     .overlay(ContextBridge().hidden())
   ```
3. Run on **My Mac (Designed for iPad)** → tap **Become Host**.
4. Open **Settings → Host QR** and scan it from another device via **Settings → Join via QR**.

## Development Notes
- **Epochs**: Host increments Epoch whenever hostship changes. Peers accept ops only from the highest Epoch.
- **OpLog**: Host assigns `seq` to accepted ops and broadcasts them. Periodically write checkpoints for fast joins.
- **LWW**: Host-authored `timeStamp`; fields merge by max `op.time` at host (ties: authorDevice).
- **Claims/Leases**: First-writer-wins enforced by host ordering; leases auto-expire or can be unclaimed.
- **Security (v1)**: QR encodes `{sessionID, host, port, secret, epoch}`. HMAC wrappers included; enable per-frame signing when ready. TLS pinning can be added later.
- **Images**: Blobs are named by sha256; transfers are chunked (64KB) and resumable by byte-range requests.

## Roadmap
- Add per-frame HMAC nonce/signing.
- Add TLS with certificate pinning.
- Warm mirror / host promotion UI polish.
- Background fetch policies and throttling.
- Cloud archive export after session completion.

## License
MIT (or your choice).