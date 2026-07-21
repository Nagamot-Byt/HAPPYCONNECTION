# Integration Test Plan — Network Health Check Module

This document describes manual integration testing steps for each supported
platform. Automated unit tests cover the Dart layer; this plan covers the
native platform channel implementations.

## Prerequisites

- Flutter SDK 3.7+
- Device/emulator for each target platform
- For desktop: Administrator / root access for DNS flush and ARP cache tests

---

## 1. Windows

### 1.1 flushDns
1. Run the app **as Administrator** (right-click → Run as administrator)
2. Trigger `flushDns` via the `runFullDiagnostics` flow
3. **Expected:** returns `true`
4. Run the app **without** Administrator privileges
5. Trigger `flushDns`
6. **Expected:** `NetworkDiagnosticsException` with `elevationRequired == true`

### 1.2 clearNetworkCaches
1. Run as Administrator
2. Trigger `clearNetworkCaches`
3. **Expected:** returns `true`

### 1.3 ping
1. With active internet, ping `8.8.8.8` (count=4, timeout=2000)
2. **Expected:** returns latency ~10-100ms (integer)
3. Ping an unreachable host (e.g., `10.255.255.1`)
4. **Expected:** returns `null` after retry

### 1.4 Spanish Windows
1. Set Windows display language to Spanish
2. Run ping — verify the "Media = XXms" parsing path works
3. **Expected:** latency correctly parsed

---

## 2. macOS

### 2.1 flushDns
1. Run app with `sudo` from terminal: `sudo flutter run -d macos`
2. Trigger `flushDns`
3. **Expected:** returns `true`
4. Run app **without** sudo
5. Trigger `flushDns`
6. **Expected:** `NetworkDiagnosticsException` with `elevationRequired == true`

### 2.2 clearNetworkCaches
1. Run with sudo
2. Trigger `clearNetworkCaches`
3. **Expected:** returns `true`

### 2.3 ping
1. Ping `8.8.8.8`
2. **Expected:** avg latency parsed from `round-trip min/avg/max/stddev`
3. Ping unreachable host → `null`

---

## 3. Linux

### 3.1 flushDns
1. Run with sudo: `sudo flutter run -d linux`
2. Trigger `flushDns`
3. **Expected:** tries `resolvectl flush-caches` → if fails, tries `systemd-resolve --flush-caches` → if fails, tries `/etc/init.d/nscd restart`
4. At least one should succeed on a typical systemd-based distro
5. Run without sudo → `elevationRequired` error

### 3.2 clearNetworkCaches
1. Run with sudo
2. Trigger `clearNetworkCaches`
3. **Expected:** `sudo ip neigh flush all` succeeds

### 3.3 ping
1. Ping `8.8.8.8`
2. **Expected:** latency parsed from `rtt min/avg/max/mdev`
3. Ping unreachable host → `null`

---

## 4. Android

### 4.1 flushDns (No-op)
1. Trigger `flushDns`
2. **Expected:** returns `true` immediately (no-op)
3. Check logcat for: `flushDns: no-op on Android (sandboxed)`

### 4.2 clearNetworkCaches (No-op)
1. Trigger `clearNetworkCaches`
2. **Expected:** returns `true` immediately
3. Check logcat for: `clearNetworkCaches: no-op on Android (sandboxed)`

### 4.3 ping (TCP connect proxy)
1. On a network with internet, ping `8.8.8.8`
2. **Expected:** TCP connect to port 3389 succeeds, returns latency in ms
3. If port 3389 is blocked (corporate firewall), falls back to DNS resolution time
4. Ping unreachable host → `null`
5. **Note:** ICMP is not used; we connect TCP port 3389

---

## 5. iOS

### 5.1 flushDns (No-op)
1. Trigger `flushDns`
2. **Expected:** returns `true` immediately
3. Check console for: `flushDns: no-op on iOS (sandboxed)`

### 5.2 clearNetworkCaches (No-op)
1. Trigger `clearNetworkCaches`
2. **Expected:** returns `true` immediately

### 5.3 ping (TCP connect proxy via Network.framework)
1. Ping `8.8.8.8` with iOS simulator or device
2. **Expected:** NWConnection TCP connect to port 3389
3. Falls back to CFHost DNS resolution if TCP connect fails
4. Ping unreachable host → `null`
5. **Note:** Uses Network.framework (NWConnection) — no raw sockets needed

---

## 6. Full Diagnostics Flow

1. Tap "Connect" on the home screen
2. **Expected sequence:**
   - DNS flushed (or no-op) → success
   - Caches cleared (or no-op) → success
   - Ping to 8.8.8.8 → latency shown
   - Split tunnel enabled → success
   - RDP client launched
3. On mobile: steps proceed quickly (no-ops are instant)

---

## 7. Error Resilience

| Scenario | Expected Behavior |
|---|---|
| No internet | Ping returns null, UI shows "⚠ Sin conectividad" |
| No elevation (desktop) | Elevation error surfaced, UI can prompt user |
| Command not found (Linux) | Graceful fallback through alternatives |
| Timeout (any platform) | Returns null/false, no crash |
| Missing plugin (platform) | Returns false/null, logged warning |
| Rapid retries | Each call independent, no state corruption |

---

## 8. Automated Test Verification

```bash
# Run all Dart unit tests
cd medlink_connect
flutter test test/health_check/
```

Expected: all tests pass — parser tests, mock channel tests, error handling tests.
