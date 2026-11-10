import Cocoa
import FlutterMacOS
import Network
import SystemConfiguration

/// Helper: run a shell command synchronously and capture output + exit code
func runShellSync(_ command: String) -> (exitCode: Int32, output: String) {
  let task = Process()
  let pipe = Pipe()
  task.launchPath = "/bin/sh"
  task.arguments = ["-c", command]
  task.standardOutput = pipe
  task.standardError = pipe
  do {
    if #available(macOS 10.13, *) {
      try task.run()
    } else {
      task.launch()
    }
  } catch {
    return (127, "Fallo al lanzar proceso: \(error.localizedDescription)")
  }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  task.waitUntilExit()
  let output = String(data: data, encoding: .utf8) ?? ""
  return (task.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
}

/// Helper: check if the caller is root / sudo'd (required for route changes).
func isRootOrAdmin() -> Bool {
  // For macOS route changes we need sudo. Simplest check: run `sudo -n true`
  let r = runShellSync("/usr/bin/sudo -n true 2>&1")
  return r.exitCode == 0
}

func matches(_ value: String, _ pattern: String) -> Bool {
  return value.range(of: pattern, options: .regularExpression) != nil
}

func isSafeHost(_ value: String) -> Bool {
  return matches(value, "^[A-Za-z0-9._:%-]+$")
}

func isSafeCIDR(_ value: String) -> Bool {
  return matches(value, "^[0-9]{1,3}(\\.[0-9]{1,3}){3}(/[0-9]{1,2})?$")
}

func isSafeIPv4(_ value: String) -> Bool {
  return matches(value, "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$")
}

func isSafeInterface(_ value: String) -> Bool {
  return matches(value, "^[A-Za-z0-9_.:-]+$")
}

func utf8Encode(_ value: String) -> String {
  // Percent-encode URI components per RFC 3986 unreserved keep
  var allowed = CharacterSet.alphanumerics
  allowed.insert(charactersIn: "-._~")
  return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

func rdpHandlerAvailable() -> Bool {
  let probes = [
    "rdp://example.com",
    "ms-rd-web://example.com",
  ]
  if #available(macOS 10.15, *) {
    for probe in probes {
      if let url = URL(string: probe),
         NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
        return true
      }
    }
  }
  return false
}

// MARK: - Network Diagnostics Plugin
class NetworkDiagnosticsPlugin {
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.medlinkconnect/network_diagnostics",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "flushDns":
        DispatchQueue.global(qos: .userInitiated).async {
          let r1 = runShellSync("/usr/bin/dscacheutil -flushcache 2>&1")
          _ = runShellSync("/usr/bin/killall -HUP mDNSResponder 2>&1 || /usr/bin/killall mDNSResponderHelper 2>&1 || true")
          let response: Any = r1.exitCode == 0
            ? "Caché DNS limpiada exitosamente (dscacheutil + mDNSResponder)."
            : FlutterError(code: "flushdns_error",
                           message: "Error al limpiar caché DNS. Ejecuta con sudo.",
                           details: nil)
          DispatchQueue.main.async { result(response) }
        }

      case "clearNetworkCaches":
        DispatchQueue.global(qos: .userInitiated).async {
          guard isRootOrAdmin() else {
            DispatchQueue.main.async {
              result(FlutterError(code: "permiso_denegado",
                                  message: "Se requieren privilegios sudo para limpiar ARP.",
                                  details: nil))
            }
            return
          }
          let r1 = runShellSync("/sbin/route -n flush 2>&1 || true")
          let r2 = runShellSync("/usr/sbin/arp -a -d 2>&1 || true")
          var msg = ""
          msg += "flush: " + (r1.exitCode == 0 ? "OK" : "fallido (\(r1.exitCode))")
          msg += " | ARP clear: " + (r2.exitCode == 0 ? "OK" : "fallido (\(r2.exitCode))")
          DispatchQueue.main.async { result(msg) }
        }

      case "ping":
        var host = "8.8.8.8"
        if let args = call.arguments as? [String: Any],
           let h = args["host"] as? String {
          host = h
        }
        guard isSafeHost(host) else {
          result(FlutterError(code: "argumento_invalido",
                              message: "Host contiene caracteres no permitidos",
                              details: nil))
          return
        }
        // Network.framework does not expose raw ICMP to sandboxed apps.
        // Probe the RDP port instead so the latency matches the actual service.
        let probePort: UInt16 = 3389
        let connection = NWConnection(
          host: NWEndpoint.Host(host),
          port: NWEndpoint.Port(rawValue: probePort)!,
          using: .tcp
        )
        let startTime = Date()
        var didFire = false
        let queue = DispatchQueue(label: "medlink.macos.ping")
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
                                    message: "Host inaccesible (TCP \(probePort) cerrado o sin ruta).",
                                    details: nil))
              }
            }
          default:
            break
          }
        }
        queue.asyncAfter(deadline: .now() + 5) {
          guard !didFire else { return }
          didFire = true
          connection.cancel()
          DispatchQueue.main.async {
            result(FlutterError(code: "timeout",
                                message: "Prueba TCP \(probePort) agotada 5s",
                                details: nil))
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
        let queue = DispatchQueue(label: "medlink.macos.tcp")
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
        queue.asyncAfter(deadline: .now() + 5.0) {
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

// MARK: - Route Manager Plugin
class RouteManagerPlugin {
  private static var trackedRoutes: [String] = []

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.medlinkconnect/route_manager",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      let privilegedMethods = [
        "addRoute",
        "enableSplitTunnel",
      ]
      if privilegedMethods.contains(call.method) {
        result(FlutterError(
          code: "no_soportado",
          message: "macOS requiere un helper privilegiado (SMAppService) para modificar rutas. "
            + "El split tunnel no está disponible en esta compilación.",
          details: nil))
        return
      }
      switch call.method {
      case "addRoute":
        guard let args = call.arguments as? [String: Any],
              let dest = args["destinationCidr"] as? String,
              let gw = args["gateway"] as? String,
              let iface = args["interfaceName"] as? String else {
          result(FlutterError(code: "argumento_invalido",
                              message: "Faltan parámetros",
                              details: nil))
          return
        }
        guard isSafeCIDR(dest), isSafeIPv4(gw), isSafeInterface(iface) else {
          result(FlutterError(code: "argumento_invalido",
                              message: "Parámetros de ruta inválidos",
                              details: nil))
          return
        }
        guard isRootOrAdmin() else {
          result(FlutterError(code: "permiso_denegado",
                              message: "Requiere sudo para cambiar rutas.",
                              details: nil))
          return
        }
        let cmd = "/sbin/route -n add \(dest) \(gw) -ifscope \(iface) 2>&1"
        let r = runShellSync(cmd)
        if r.exitCode != 0 {
          let fallback = "/sbin/route -n add \(dest) \(gw) 2>&1"
          let r2 = runShellSync(fallback)
          if r2.exitCode != 0 {
            result(FlutterError(code: "error_comando",
                                message: "Error al agregar ruta: \(r.output.isEmpty ? r2.output : r.output)",
                                details: nil))
            return
          }
        }
        result("Ruta \(dest) agregada exitosamente.")

      case "removeRoute":
        result("La ruta no se modifica en macOS sin helper privilegiado; nada que limpiar.")

      case "enableSplitTunnel":
        guard let args = call.arguments as? [String: Any],
              let subnets = args["hospitalSubnets"] as? [String],
              let gw = args["gateway"] as? String,
              let iface = args["interfaceName"] as? String else {
          result(FlutterError(code: "argumento_invalido",
                              message: "Se requieren hospitalSubnets, gateway, interfaceName.",
                              details: nil))
          return
        }
        guard isSafeIPv4(gw), isSafeInterface(iface),
              subnets.allSatisfy({ isSafeCIDR($0.trimmingCharacters(in: .whitespaces)) }) else {
          result(FlutterError(code: "argumento_invalido",
                              message: "Parámetros de túnel inválidos",
                              details: nil))
          return
        }
        guard isRootOrAdmin() else {
          result(FlutterError(code: "permiso_denegado",
                              message: "Se requieren privilegios sudo.",
                              details: nil))
          return
        }
        var added: [String] = []
        for subnet in subnets {
          let trimmed = subnet.trimmingCharacters(in: .whitespaces)
          guard !trimmed.isEmpty else { continue }
          let cmd = "/sbin/route -n add \(trimmed) \(gw) -ifscope \(iface) 2>&1"
          let r = runShellSync(cmd)
          if r.exitCode != 0 {
            let fallback = "/sbin/route -n add \(trimmed) \(gw) 2>&1"
            let r2 = runShellSync(fallback)
            if r2.exitCode != 0 {
              // Rollback
              for prev in added {
                runShellSync("/sbin/route -n delete \(prev) 2>&1")
              }
              result(FlutterError(code: "error_tunel_dividido",
                                  message: "Error en ruta \(trimmed). Se revirtieron los cambios.",
                                  details: nil))
              return
            }
          }
          added.append(trimmed)
        }
        trackedRoutes.append(contentsOf: added)
        result("Túnel dividido habilitado exitosamente. \(added.count) ruta(s) agregada(s).")

      case "disableSplitTunnel":
        trackedRoutes.removeAll()
        result("No hay rutas de túnel dividido que limpiar en macOS.")

      case "getRoutes":
        DispatchQueue.global(qos: .userInitiated).async {
          let r = runShellSync("/sbin/netstat -rn 2>&1")
          DispatchQueue.main.async { result(r.output) }
        }

      case "getPrimaryDefaultRouteInfo":
        var info: [String: String] = [
          "interfaceName": "",
          "gateway": "",
          "routeMetric": ""
        ]
        if let store = SCDynamicStoreCreate(
          nil, "MedLinkConnect" as CFString, nil, nil
        ), let value = SCDynamicStoreCopyValue(
          store, "State:/Network/Global/IPv4" as CFString
        ) as? [String: Any] {
          info["interfaceName"] = value["PrimaryInterface"] as? String ?? ""
          info["gateway"] = value["Router"] as? String ?? ""
        }
        result(info)

      case "listInterfaces":
        DispatchQueue.global(qos: .userInitiated).async {
          // Preferred: `networksetup -listallhardwareports`
          let r = runShellSync("/usr/sbin/networksetup -listallhardwareports 2>&1")
          var out: [String] = []
          for line in r.output.split(separator: "\n") {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("Device: ") {
              let iface = String(s.dropFirst("Device: ".count))
                .trimmingCharacters(in: .whitespaces)
              if !iface.isEmpty { out.append(iface) }
            }
          }
          if out.isEmpty {
            // Fallback: ifconfig
            let r2 = runShellSync("/sbin/ifconfig -l 2>&1")
            out = r2.output.split(separator: " ").map(String.init)
          }
          DispatchQueue.main.async { result(out) }
        }

      case "verifyRoutes":
        // Sin helper privilegiado no se aplican rutas; no hay nada que
        // verificar en este equipo.
        result([String]())

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

// MARK: - RDP Launcher Plugin
class RdpLauncherPlugin {
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.medlinkconnect/rdp_launcher",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "preLaunch":
        if rdpHandlerAvailable() {
          result(true)
        } else {
          result(FlutterError(code: "sin_manejador_rdp",
                              message: "Instala Microsoft Remote Desktop desde App Store.",
                              details: nil))
        }

      case "isRdpClientAvailable":
        result(rdpHandlerAvailable())

      case "launchRdp":
        guard let args = call.arguments as? [String: Any],
              let host = args["host"] as? String else {
          result(FlutterError(code: "argumento_invalido",
                              message: "Falta host", details: nil))
          return
        }
        let port = (args["port"] as? Int) ?? 3389
        let username = args["username"] as? String ?? ""
        let domain = args["domain"] as? String ?? ""
        let webFeed = (args["useWebFeed"] as? Bool) ?? false

        guard port > 0 && port <= 65535 else {
          result(FlutterError(code: "argumento_invalido",
                              message: "Puerto inválido", details: nil))
          return
        }

        var uri = ""
        if webFeed {
          uri = "ms-rd-web://" + utf8Encode(host)
        } else {
          var authority = ""
          var userInfo = ""
          if !domain.isEmpty { userInfo += domain + "\\" }
          if !username.isEmpty { userInfo += username }
          if !userInfo.isEmpty { authority += utf8Encode(userInfo) + "@" }
          authority += "\(utf8Encode(host)):\(port)"
          uri = "rdp://" + authority
        }

        var candidates = [uri]
        if !webFeed {
          candidates.append("ms-rd-web://" + utf8Encode(host))
        }
        // Primary: NSWorkspace.open
        for candidate in candidates {
          guard let url = URL(string: candidate) else { continue }
          if NSWorkspace.shared.open(url) {
            result("Conexión RDP lanzada a \(host):\(port) correctamente.")
            return
          }
        }
        // Fallback: shell open
        DispatchQueue.global(qos: .userInitiated).async {
          var lastOutput = ""
          for candidate in candidates {
            let r = runShellSync("/usr/bin/open \(candidate.shellQuoted) 2>&1")
            if r.exitCode == 0 {
              DispatchQueue.main.async {
                result("Conexión RDP lanzada a \(host):\(port) correctamente.")
              }
              return
            }
            lastOutput = r.output
          }
          DispatchQueue.main.async {
            result(FlutterError(code: "lanzamiento_fallido",
                                message: "No se pudo lanzar cliente RDP: \(lastOutput)",
                                details: nil))
          }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

private extension String {
  var shellQuoted: String {
    return "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    NetworkDiagnosticsPlugin.register(with: flutterViewController)
    RouteManagerPlugin.register(with: flutterViewController)
    RdpLauncherPlugin.register(with: flutterViewController)

    super.awakeFromNib()
  }
}
