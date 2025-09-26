# LANSyncApp Addons (drop-in code)

Drag the **Addons** folder into your existing Xcode project (target: LANSyncApp). 
These files provide the missing scaffolding for networking (Bonjour + Network.framework), 
operation log, content-addressed blobs with resumable transfers, QR join, and HMAC framing.

**After adding:**
1) Add `ContextBridge()` to your `RootView` (e.g., at the bottom of the VStack) so the Replicator gets a SwiftData context:
   ```swift
   VStack { /* ... */ }
   .overlay(ContextBridge().hidden())
   ```
2) Replace the stub logic inside `SessionManager` with calls to `HostService.shared` and `VerifierService.shared` as desired.
   (You can also rename or remove the stub implementations—these Addons compile even if you keep the stubs and integrate gradually.)

The code is intentionally light and commented so you can extend features incrementally.
