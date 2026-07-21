# MedLink Connect

**Cross-platform network facilitator for hospital RDP access.**

MedLink Connect is a Flutter application that eliminates the friction of connecting to hospital Windows Servers via RDP. It automatically diagnoses and repairs network issues (DNS flush, cache clearing, ping verification), enforces split-tunneling so the hospital's isolated WiFi ("HIS") doesn't kill the user's internet, and then hands off to Microsoft's official Remote Desktop client via deep linking — no custom RDP viewer, zero visual glitches.

## Target Platforms

| Platform | Status |
|----------|--------|
| Windows  | ✅     |
| macOS    | ✅     |
| Linux    | ✅     |
| iOS      | ✅     |
| Android  | ✅     |

## Architecture

```
lib/
  core/                         # Shared abstractions
    network_diagnostics.dart    #   DNS flush, cache clear, ping interface
    route_manager.dart          #   Static route / split-tunnel interface
    rdp_launcher.dart           #   RDP URI launching interface
    app_theme.dart              #   Material 3 theme
  features/
    health_check/
      default_network_diagnostics.dart  # Platform channel impl
    split_tunnel/
      default_route_manager.dart        # Platform channel impl
    rdp_launcher/
      default_rdp_launcher.dart         # Platform channel impl
    ui/
      home_screen.dart                  # Main UI
  main.dart
```

All platform-specific code is behind abstract Dart interfaces (`NetworkDiagnostics`, `RouteManager`, `RdpLauncher`). Default implementations use Flutter method channels (`com.medlinkconnect/*`) so each platform can provide native implementations without coupling to the shared Dart layer.

## Building

### Prerequisites

- Flutter SDK ≥ 3.29 (stable)
- Dart ≥ 3.7
- Platform SDKs as needed (Xcode for iOS/macOS, Android SDK for Android, Visual Studio for Windows, GTK for Linux)

### Get dependencies

```bash
cd medlink_connect
flutter pub get
```

### Run on desktop

```bash
# Windows (requires Visual Studio 2022 with Desktop C++)
flutter run -d windows

# macOS
flutter run -d macos

# Linux (requires GTK 3 development libraries)
sudo apt-get install libgtk-3-dev
flutter run -d linux
```

### Run on mobile

```bash
# Android
flutter run -d <android-device>

# iOS (macOS host only, requires Xcode)
flutter run -d <ios-device>
```

### Analyze

```bash
flutter analyze
```

## Deep Linking

MedLink Connect registers as a handler for the following URI schemes:

- `rdp://` — Legacy RDP deep link format
- `ms-rd-web://` — Microsoft Remote Desktop web feed format

These are configured in each platform's manifest:

- **Android**: `AndroidManifest.xml` intent filters
- **iOS / macOS**: `Info.plist` `CFBundleURLTypes`
- **Windows**: Registry registration (TBD — manual install step or MSI installer)
- **Linux**: `.desktop` file MIME type and scheme registration

When a user taps "Connect" in the app, MedLink Connect prepares the network and then launches the system's default handler for the `rdp://` scheme — which should be the Microsoft Remote Desktop client.

## Features

### 1. Network Diagnostics
- **DNS flush**: Clears the OS DNS resolver cache
- **Cache clear**: Clears ARP tables and other network caches
- **Ping check**: Verifies connectivity to a configurable host (default: 8.8.8.8)

### 2. Split Tunneling
- Desktop: policy-based routing rules that direct only hospital subnet traffic through the segregated WiFi
- Mobile: per-app VPN profile provisioning (managed via MDM or manually)

### 3. RDP Launcher
- Hands off to Microsoft Remote Desktop (or compatible client) via `rdp://` or `ms-rd-web://` URI
- Pre-fills address, port, and username from configuration
- Detects whether an RDP client is available

## License

Proprietary — MedLink Connect is a commercial B2B SaaS product. All rights reserved.
