import Cocoa
import FlutterMacOS
import Network

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
        // Ping with 4 probes, wait 2s each.
        DispatchQueue.global(qos: .userInitiated).async {
          let cmd = "/sbin/ping -c 4 -W 2000 \(host) 2>&1"
          let r = runShellSync(cmd)
          if r.exitCode != 0 {
            DispatchQueue.main.async {
              result(FlutterError(code: "inaccesible",
                                  message: "Host inaccesible",
                                  details: nil))
            }
            return
          }
          // Parse round-trip min/avg/max/stddev = X/Y/Z/W ms
          let pattern = "round-trip min/avg/max/stddev = ([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+) ms"
          guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            DispatchQueue.main.async {
              result(FlutterError(code: "ping_error", message: "Respuesta inesperada", details: nil))
            }
            return
          }
          let nsrange = NSRange(r.output.startIndex..<r.output.endIndex, in: r.output)
          if let match = regex.firstMatch(in: r.output, options: [], range: nsrange),
             let avgRange = Range(match.range(at: 2), in: r.output) {
            let avgStr = String(r.output[avgRange])
            if let avg = Double(avgStr) {
              DispatchQueue.main.async { result(Int(avg.rounded())) }
              return
            }
          }
          DispatchQueue.main.async {
            result(FlutterError(code: "ping_error", message: "No se pudo parsear ping", details: nil))
          }
        }

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
        "removeRoute",
        "enableSplitTunnel",
        "disableSplitTunnel",
        "verifyRoutes",
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
        guard let args = call.arguments as? [String: Any],
              let dest = args["destinationCidr"] as? String else {
          result(FlutterError(code: "argumento_invalido",
                              message: "Falta destinationCidr",
                              details: nil))
          return
        }
        guard isSafeCIDR(dest) else {
          result(FlutterError(code: "argumento_invalido",
                              message: "CIDR inválido",
                              details: nil))
          return
        }
        let gw = (args["gateway"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let iface = (args["interfaceName"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        if !gw.isEmpty && !isSafeIPv4(gw) {
          result(FlutterError(code: "argumento_invalido",
                              message: "Gateway inválido",
                              details: nil))
          return
        }
        let target = gw.isEmpty ? dest : "\(dest) \(gw)"
        let cmd = "/sbin/route -n delete \(target) 2>&1"
        let r = runShellSync(cmd)
        if r.exitCode != 0 {
          let lower = r.output.lowercased()
          if lower.contains("not in table") || lower.contains("no such process") {
            result("La ruta \(dest) ya no existe.")
            return
          }
          result(FlutterError(code: "error_comando",
                              message: "Error al eliminar ruta: \(r.output)",
                              details: nil))
          return
        }
        result("Ruta \(dest) eliminada.")

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
        guard isRootOrAdmin() else {
          result(FlutterError(code: "permiso_denegado",
                              message: "Requiere sudo.", details: nil))
          return
        }
        let current = trackedRoutes
        trackedRoutes.removeAll()
        guard !current.isEmpty else {
          result("No hay rutas de túnel dividido activas.")
          return
        }
        var msgs: [String] = []
        for dest in current {
          let r = runShellSync("/sbin/route -n delete \(dest) 2>&1")
          if r.exitCode == 0 {
            msgs.append("Ruta \(dest) eliminada.")
          } else {
            msgs.append("Error al eliminar \(dest): \(r.output)")
          }
        }
        result(msgs.joined(separator: " "))

      case "getRoutes":
        DispatchQueue.global(qos: .userInitiated).async {
          let r = runShellSync("/sbin/netstat -rn 2>&1")
          DispatchQueue.main.async { result(r.output) }
        }

      case "getPrimaryDefaultRouteInfo":
        DispatchQueue.global(qos: .userInitiated).async {
          var info: [String: String] = [
            "interfaceName": "",
            "gateway": "",
            "routeMetric": ""
          ]
          let r = runShellSync("/usr/sbin/route -n get default 2>&1")
          for rawLine in r.output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("gateway:") {
              info["gateway"] = String(line.dropFirst("gateway:".count))
                .trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("interface:") {
              info["interfaceName"] = String(line.dropFirst("interface:".count))
                .trimmingCharacters(in: .whitespaces)
            }
          }
          DispatchQueue.main.async { result(info) }
        }

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
        guard let args = call.arguments as? [String: Any],
              let subnets = args["hospitalSubnets"] as? [String] else {
          result(FlutterError(code: "argumento_invalido",
                              message: "Se requieren hospitalSubnets, gateway, interfaceName.",
                              details: nil))
          return
        }
        let routeTable = runShellSync("/sbin/netstat -rn 2>&1").output
        let missing = subnets
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty && !routeTable.contains($0) }
        result(missing)

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
        DispatchQueue.global(qos: .userInitiated).async {
          // Check either `open rdp://` handler or Microsoft Remote Desktop / CoRD
          let r = runShellSync("/usr/bin/osascript -e 'id of application \"Microsoft Remote Desktop\"' 2>&1")
          let scheme = runShellSync("/usr/bin/open -Ra \"rdp:\" 2>&1")
          DispatchQueue.main.async {
            if r.exitCode == 0 || scheme.exitCode == 0 {
              result(true)
            } else {
              result(FlutterError(code: "sin_manejador_rdp",
                                  message: "Instala Microsoft Remote Desktop desde App Store.",
                                  details: nil))
            }
          }
        }

      case "isRdpClientAvailable":
        DispatchQueue.global(qos: .userInitiated).async {
          // Apps known to handle RDP
          let apps = [
            "Microsoft Remote Desktop",
            "Microsoft Remote Desktop Beta",
            "CoRD",
            "Royal TSX",
            "Jump Desktop",
          ]
          for app in apps {
            let r = runShellSync("/usr/bin/osascript -e 'id of application \"" + app + "\"' 2>&1")
            if r.exitCode == 0 {
              DispatchQueue.main.async { result(true) }
              return
            }
          }
          // Scheme handler?
          let scheme = runShellSync("/usr/bin/open -Ra \"rdp:\" > /dev/null 2>&1")
          DispatchQueue.main.async { result(scheme.exitCode == 0) }
        }

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

        // Primary: NSWorkspace.open
        if let url = URL(string: uri) {
          let opened = NSWorkspace.shared.open(url)
          if opened {
            result("Conexión RDP lanzada a \(host):\(port) correctamente.")
            return
          }
        }
        // Fallback: shell open
        DispatchQueue.global(qos: .userInitiated).async {
          let r = runShellSync("/usr/bin/open \(uri.shellQuoted) 2>&1")
          DispatchQueue.main.async {
            if r.exitCode == 0 {
              result("Conexión RDP lanzada a \(host):\(port) correctamente.")
            } else {
              result(FlutterError(code: "lanzamiento_fallido",
                                  message: "No se pudo lanzar cliente RDP: \(r.output)",
                                  details: nil))
            }
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
