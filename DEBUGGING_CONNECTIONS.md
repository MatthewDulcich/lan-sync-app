# Connection Debugging Guide

## Current Status
I've added comprehensive debugging output to help identify connection issues. Here's what to look for:

## Debug Output Locations

### 1. HostService Debug Messages
- `HostService: Starting with epoch X`
- `HostService: Port ready: X`
- `HostService: Setting up new connection from client`
- `HostService: Client connection ready`

### 2. VerifierService Debug Messages
- `VerifierService: Attempting to connect to X:X`
- `VerifierService: Connection state changed to X`
- `VerifierService: Connection ready, sending hello message`
- `VerifierService: Received heartbeat - epoch: X`

### 3. PeerDiscovery Debug Messages
- `PeerDiscovery: Starting to advertise with name: X`
- `PeerDiscovery: Found service: X`
- `PeerDiscovery: Service resolved: X`

### 4. SessionManager Debug Messages
- `SessionManager: Attempting to join session`
- `SessionManager: Starting VerifierService connection...`

## Testing Steps

### Step 1: Test Host Startup
1. Build and run the app
2. Tap "Become Host" 
3. Look for these messages in the console:
   ```
   HostService: Starting with epoch 1
   HostService: Port ready: [some_port_number]
   PeerDiscovery: Starting to advertise with name: [session_id]
   PeerDiscovery: Service published successfully: [session_id]
   ```

### Step 2: Test QR Code Generation
1. Go to Settings → Host QR
2. Look for:
   ```
   HostQRView: Checking HostService port...
   HostQRView: HostService port ready: [port_number]
   ```

### Step 3: Test Service Discovery
1. On another device, go to Settings → Join via QR
2. Look for:
   ```
   PeerDiscovery: Starting to browse for service type: _lansyncmeta._tcp.
   PeerDiscovery: Found service: [service_name]
   PeerDiscovery: Service resolved: [service_name] at [ip_address] port [port]
   ```

### Step 4: Test Connection
1. When joining via QR, look for:
   ```
   SessionManager: Attempting to join session
   VerifierService: Attempting to connect to [host]:[port]
   VerifierService: Connection state changed to ready
   VerifierService: Connection ready, sending hello message
   ```

2. On the host side, look for:
   ```
   HostService: Setting up new connection from client
   HostService: Client connection ready
   ```

## Common Issues & Solutions

### Issue: No "Port ready" message
- **Problem**: HostService failed to start
- **Solution**: Check App Sandbox entitlements include network server permissions

### Issue: "Service failed to publish" 
- **Problem**: Bonjour advertising failed
- **Solution**: Verify Info.plist has NSLocalNetworkUsageDescription and NSBonjourServices

### Issue: "Found service" but no "Service resolved"
- **Problem**: Service discovery working but resolution failing
- **Solution**: Check network permissions and firewall settings

### Issue: "Connection state changed to failed"
- **Problem**: TCP connection cannot be established
- **Solution**: 
  - Verify host is still running
  - Check if ports are blocked by firewall
  - Ensure both devices are on same network

### Issue: Connection established but no heartbeat
- **Problem**: Message framing or encoding issues
- **Solution**: Check MessageFramer debug output for encoding/decoding errors

## Network Requirements

### macOS Permissions
- App must have "Incoming Connections (Server)" and "Outgoing Connections (Client)" in App Sandbox
- Info.plist must include NSLocalNetworkUsageDescription
- Info.plist must include NSBonjourServices with both service types

### iOS Permissions  
- Info.plist must include NSLocalNetworkUsageDescription
- Info.plist must include NSBonjourServices
- User may need to grant local network permission in Settings

### Network Environment
- Both devices must be on same local network
- Network must allow peer-to-peer TCP connections
- Firewall must allow the app's network traffic

## Next Steps

1. **Run the app and capture console output** - All the debug messages will help identify exactly where the connection is failing

2. **Test on same device first** - Try hosting on Mac and joining via localhost to isolate network vs. framework issues

3. **Check system logs** - Look for any denied network permissions in Console.app

4. **Test service discovery independently** - Use network debugging tools to verify Bonjour services are being advertised correctly