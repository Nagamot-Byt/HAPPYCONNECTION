import Flutter
import UIKit
import Network

// MARK: Helpers
fileprivate func runShellSync(_ command: String) -> (exitCode: Int32, output: String) {
  // iOS apps are sandboxed. Shell exec is not allowed in production App Store builds
  // (fork+exec forbidden). We use a best-effort approach: ping via Network.framework,
  // but for consistency we provide the helper (limited to no-op in prod for commands not
  // supported without NetworkExtension).
  let swift = command
  _ = swift // suppress unused
  return (127, "Shell no disponible en iOS sandboxed; se usan APIs nativas.")
}

fileprivate func percentEncode(_ value: String) -> String {
  var allowed = CharacterSet.alphanumerics
  allowed.insert(charactersIn: "-._~")
  return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

fileprivate func parsePingAvg(_ output: String) -> Int? {
  let patterns = [
    "round-trip min/avg/max/stddev = ([0-9.]+)/([0-9.]+)/",
    "= [0-9.]+/([0-9.]+)/"
  ]
  for p in patterns {
    guard let regex = try? NSRegularExpression(pattern: p, options: []) else { continue }
    let nsrange = NSRange(output.startIndex..<output.endIndex, in: output)
    if let match = regex.firstMatch(in: output, options: [], range: nsrange) {
      var groupIdx = 2
      if match.numberOfRanges <= groupIdx { groupIdx = 1 }
      if let r = Range(match.range(at: groupIdx), in: output) {
        if let avg = Double(String(output[r])) {
          return Int(avg.rounded())
        }
      }
    }
  }
  return nil
}

// MARK: - Network Diagnostics
fileprivate class NetworkDiagnosticsPlugin {
  static func register(with vc: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.medlinkconnect/network_diagnostics",
      binaryMessenger: vc.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "flushDns":
        // iOS: There is no public API to flush the DNS resolver cache. We still return OK
        // indicating that the app recycled its own URLSession, plus inform the user.
        URLCache.shared.removeAllCachedResponses()
        result("No hay API pública iOS para flush DNS; cache URLSession limpiado.")

      case "clearNetworkCaches":
        URLCache.shared.removeAllCachedResponses()
        // Clear cookie storage too
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        result("Cache de URLSession y cookies limpiadas.")

      case "ping":
        var host = "8.8.8.8"
        if let args = call.arguments as? [String: Any],
           let h = args["host"] as? String {
          host = h
        }
        // Network.framework does not expose raw ICMP to sandboxed apps.
        // Probe the RDP port instead of an arbitrary web port so the result
        // matches the service the app is actually trying to reach.
        let probePort: UInt16 = 3389
        let connection = NWConnection(
          host: NWEndpoint.Host(host),
          port: NWEndpoint.Port(rawValue: probePort)!,
          using: .tcp
        )
        let startTime = Date()
        var didFire = false
        let queue = DispatchQueue(label: "medlink.ping")
        connection.stateUpdateHandler = { state in
          guard !didFire else { return }
          switch state {
          case .ready:
            let ms = Int(Date().timeIntervalSince(startTime) * 1000)
            didFire = true
            connection.cancel()
            DispatchQueue.main.async { result(ms) }
          case .failed, .cancelled:
            if !didFire {
              didFire = true
              DispatchQueue.main.async {
                result(FlutterError(code: "inaccesible",
                                    message: "Host inaccesible en iOS (TCP \(probePort) cerrado o sin ruta).",
                                    details: nil))
              }
            }
          default: break
          }
        }
        queue.asyncAfter(deadline: .now() + 3) {
          guard !didFire else { return }
          didFire = true
          connection.cancel()
          DispatchQueue.main.async {
            result(FlutterError(code: "timeout", message: "Prueba TCP \(probePort) agotada 3s", details: nil))
          }
        }
        connection.start(queue: queue)

      case "checkTcpPort":
        guard let args = call.arguments as? [String: Any],
              let host = args["host"] as? String,
              let port = args["port"] as? Int,
              port > 0, port <= 65535 else {
          result(FlutterError(code: "argumento_invalido", message: "Host o puerto inválido", details: nil))
          return
        }

        let connection = NWConnection(
          host: NWEndpoint.Host(host),
          port: NWEndpoint.Port(rawValue: UInt16(port))!,
          using: .tcp
        )
        let start = Date()
        var completed = false
        let queue = DispatchQueue(label: "medlink.tcp")
        connection.stateUpdateHandler = { state in
          guard !completed else { return }
          switch state {
          case .ready:
            completed = true
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            connection.cancel()
            DispatchQueue.main.async { result(ms) }
          case .failed, .cancelled:
            completed = true
            DispatchQueue.main.async {
              result(FlutterError(code: "inaccesible",
                                  message: "No se pudo establecer conexión TCP con el puerto",
                                  details: nil))
            }
          default:
            break
          }
        }
        queue.asyncAfter(deadline: .now() + 2.0) {
          guard !completed else { return }
          completed = true
          connection.cancel()
          DispatchQueue.main.async {
            result(FlutterError(code: "timeout",
                                message: "Tiempo agotado validando TCP",
                                details: nil))
          }
        }
        connection.start(queue: queue)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

// MARK: - Route Manager (iOS limitations: requiere NetworkExtension)
fileprivate class RouteManagerPlugin {
  private static var trackedRoutes: [String] = []

  static func register(with vc: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.medlinkconnect/route_manager",
      binaryMessenger: vc.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      // iOS sandbox no permite modificar tabla de rutas de bajo nivel.
      // Se necesita una extensión NetworkExtension (NEPacketTunnelProvider) + provisioning
      // profile con com.apple.developer.networking.networkextension entitlement.
      // Aquí validamos y devolvemos error claro indicando al usuario.
      let neSupported: Bool = {
        // Best-effort check: ask if NEVPNManager class exists + try to read configuration
        return NSClassFromString("NEVPNManager") != nil
      }()

      switch call.method {
      case "addRoute":
        if neSupported {
          result(FlutterError(code: "requiere_network_extension",
                              message: "iOS requiere NetworkExtension (NEPacketTunnelProvider). " +
                                       "Habilítalo en Xcode: Signing & Capabilities → + Personal VPN.",
                              details: nil))
        } else {
          result(FlutterError(code: "no_soportado",
                              message: "iOS sandbox impide modificar rutas sin NetworkExtension.",
                              details: nil))
        }

      case "removeRoute":
        if let args = call.arguments as? [String: Any],
           let dest = args["destinationCidr"] as? String,
           let idx = trackedRoutes.firstIndex(of: dest) {
          trackedRoutes.remove(at: idx)
        }
        result(FlutterError(code: "requiere_network_extension",
                            message: "Usa Personal VPN (NEPacketTunnelProvider) para split tunneling real.",
                            details: nil))

      case "enableSplitTunnel":
        if let args = call.arguments as? [String: Any],
           let subnets = args["hospitalSubnets"] as? [String] {
          trackedRoutes = subnets.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        result(FlutterError(code: "requiere_network_extension",
                            message: "Split tunnel en iOS solo posible con NetworkExtension PacketTunnel. " +
                                     "Entitlements: Personal VPN. Rutas guardadas en memoria (\(trackedRoutes.count)) " +
                                     "para usar al implementar el NEPacketTunnelProvider.",
                            details: trackedRoutes))

      case "disableSplitTunnel":
        trackedRoutes.removeAll()
        result(FlutterError(code: "requiere_network_extension",
                            message: "Split tunnel desactivado (memoria). Implementa NEPacketTunnelProvider.",
                            details: nil))

      case "getRoutes":
        // Use getifaddrs / syscall no available for routes; best-effort NWPathMonitor
        // Provide a textual summary
        let summary = "Routes (iOS no expone tabla pública). Tracked en memoria: \(trackedRoutes)."
        result(summary)

      case "listInterfaces":
        // Use NetworkInterface names via NWPathMonitor + getifaddrs bridging via if_nametoindex
        var out: [String] = []
        // Walk through well-known interfaces: en0 (wifi), en1 (eth), pdp_ip0 (cel), utun0 (VPN)
        let candidates = ["en0", "en1", "pdp_ip0", "pdp_ip1", "pdp_ip2", "pdp_ip3",
                          "utun0", "utun1", "utun2", "utun3", "lo0", "bridge0", "awdl0"]
        for iface in candidates {
          let idx = if_nametoindex(iface)
          if idx != 0 {
            out.append(iface)
          }
        }
        if out.isEmpty {
          out = ["en0"] // fallback
        }
        result(out)

      case "getPrimaryDefaultRouteInfo":
        let out: [String: String] = [
          "interfaceName": "en0",
          "gateway": "",
          "routeMetric": ""
        ]
        result(out)

      case "verifyRoutes":
        if let args = call.arguments as? [String: Any],
           let subnets = args["hospitalSubnets"] as? [String] {
          let expected = subnets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
          let missing = expected.filter { !trackedRoutes.contains($0) }
          result(missing)
        } else {
          result(FlutterError(code: "argumento_invalido",
                              message: "Se requieren hospitalSubnets, gateway, interfaceName.",
                              details: nil))
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

// MARK: - RDP Launcher
fileprivate class RdpLauncherPlugin {
  static func register(with vc: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.medlinkconnect/rdp_launcher",
      binaryMessenger: vc.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "preLaunch":
        let rdps = ["rdp://", "ms-rd-web://"]
        var any = false
        for scheme in rdps {
          if let url = URL(string: scheme + "example.com") {
            if UIApplication.shared.canOpenURL(url) {
              any = true
              break
            }
          }
        }
        // Also known apps: MS Remote Desktop URL scheme rdp:// is com.microsoft.rdc.ios
        if any {
          result(true)
        } else {
          result(FlutterError(code: "sin_manejador_rdp",
                              message: "Instala Microsoft Remote Desktop desde App Store.",
                              details: nil))
        }

      case "isRdpClientAvailable":
        let schemes = ["rdp://example.com", "ms-rd-web://example.com"]
        for s in schemes {
          if let u = URL(string: s), UIApplication.shared.canOpenURL(u) {
            result(true)
            return
          }
        }
        // Try known URL scheme prefixes for Jump Desktop, etc
        let knownSchemes = ["rdp", "rdp2", "jump", "msrdc"]
        for s in knownSchemes {
          if let u = URL(string: s + "://"), UIApplication.shared.canOpenURL(u) {
            result(true)
            return
          }
        }
        result(false)

      case "launchRdp":
        guard let args = call.arguments as? [String: Any],
              let host = args["host"] as? String else {
          result(FlutterError(code: "argumento_invalido", message: "Falta host", details: nil))
          return
        }
        let port = (args["port"] as? Int) ?? 3389
        let username = args["username"] as? String ?? ""
        let domain = args["domain"] as? String ?? ""
        let webFeed = (args["useWebFeed"] as? Bool) ?? false

        guard port > 0 && port <= 65535 else {
          result(FlutterError(code: "argumento_invalido", message: "Puerto inválido", details: nil))
          return
        }

        var uri = ""
        if webFeed {
          uri = "ms-rd-web://" + percentEncode(host)
        } else {
          var authority = ""
          var userInfo = ""
          if !domain.isEmpty { userInfo += domain + "\\" }
          if !username.isEmpty { userInfo += username }
          if !userInfo.isEmpty { authority += percentEncode(userInfo) + "@" }
          authority += "\(percentEncode(host)):\(port)"
          uri = "rdp://" + authority
        }

        if let url = URL(string: uri) {
          if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { ok in
              if ok {
                result("Conexión RDP lanzada a \(host):\(port) correctamente.")
              } else {
                result(FlutterError(code: "lanzamiento_fallido",
                                    message: "Cliente RDP no pudo abrir URL.",
                                    details: nil))
              }
            }
            return
          } else {
            result(FlutterError(code: "sin_manejador_rdp",
                                message: "No hay app que maneje rdp://. Instala MS Remote Desktop.",
                                details: nil))
          }
        } else {
          result(FlutterError(code: "argumento_invalido", message: "URL inválida", details: nil))
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register custom method channels with root FlutterViewController
    if let window = self.window,
       let rootVC = window.rootViewController as? FlutterViewController {
      NetworkDiagnosticsPlugin.register(with: rootVC)
      RouteManagerPlugin.register(with: rootVC)
      RdpLauncherPlugin.register(with: rootVC)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
