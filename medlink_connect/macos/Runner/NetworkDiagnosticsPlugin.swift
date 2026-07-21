import Cocoa
import FlutterMacOS

/// macOS implementation of the `com.medlinkconnect/network_diagnostics`
/// method channel.
///
/// Provides DNS flush, ARP cache clearing, and ICMP ping via native
/// shell commands (`dscacheutil`, `killall`, `arp`, `ping`).
public class NetworkDiagnosticsPlugin: NSObject, FlutterPlugin {

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.medlinkconnect/network_diagnostics",
      binaryMessenger: registrar.messenger)
    let instance = NetworkDiagnosticsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "flushDns":
      handleFlushDns(result: result)

    case "clearNetworkCaches":
      handleClearCaches(result: result)

    case "ping":
      handlePing(call: call, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - DNS Flush

  private func handleFlushDns(result: @escaping FlutterResult) {
    // Requires elevated privileges: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
    guard isElevated() else {
      result(FlutterError(
        code: "elevation_required",
        message: "Elevation required: DNS flush needs root privileges. Run with sudo.",
        details: nil))
      return
    }

    // Run both commands
    let (out1, code1) = runCommand("dscacheutil -flushcache 2>&1")
    let (out2, code2) = runCommand("killall -HUP mDNSResponder 2>&1")

    if code1 != 0 && code2 != 0 {
      // Both failed — report the error
      let errorMsg = [out1, out2].filter { !$0.isEmpty }.joined(separator: "; ")
      if errorMsg.isEmpty {
        result(false)
      } else {
        NSLog("[NetworkDiagnosticsPlugin] DNS flush failed: \(errorMsg)")
        result(false)
      }
    } else {
      result(true)
    }
  }

  // MARK: - Cache Clear

  private func handleClearCaches(result: @escaping FlutterResult) {
    guard isElevated() else {
      result(FlutterError(
        code: "elevation_required",
        message: "Elevation required: ARP cache clear needs root privileges. Run with sudo.",
        details: nil))
      return
    }

    let (output, exitCode) = runCommand("arp -ad 2>&1")
    if exitCode != 0 && !output.isEmpty {
      NSLog("[NetworkDiagnosticsPlugin] ARP cache clear warning: \(output)")
    }
    // arp -ad often returns non-zero even when successful, so always return true
    // if elevation is available
    result(true)
  }

  // MARK: - Ping

  private func handlePing(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "bad_arguments",
                          message: "Expected a map with 'host', 'count', 'timeoutMs'.",
                          details: nil))
      return
    }

    let host = args["host"] as? String ?? "8.8.8.8"
    let count = args["count"] as? Int ?? 4
    let timeoutSec = max(1, (args["timeoutMs"] as? Int ?? 2000) / 1000)

    // macOS: ping -c {count} -W {timeout_sec} {host}
    let command = "ping -c \(count) -W \(timeoutSec) \(host) 2>&1"
    let (output, exitCode) = runCommand(command)

    if exitCode != 0 {
      // Host unreachable or ping failed — return null
      result(nil)
      return
    }

    // Parse: "round-trip min/avg/max/stddev = X/Y/Z/W ms"
    let pattern = #"min/avg/max/(?:mdev|stddev)\s*=\s*([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+)\s*ms"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      result(nil)
      return
    }

    let range = NSRange(output.startIndex..<output.endIndex, in: output)
    if let match = regex.firstMatch(in: output, options: [], range: range) {
      let avgRange = match.range(at: 2)  // group 2 = avg
      if avgRange.location != NSNotFound,
         let avgStr = Range(avgRange, in: output) {
        let avgVal = Double(output[avgStr])
        if let avg = avgVal {
          result(Int(avg.rounded()))
          return
        }
      }
    }

    result(nil)
  }

  // MARK: - Helpers

  private func runCommand(_ command: String) -> (output: String, exitCode: Int32) {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", command]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
    } catch {
      return ("Failed to launch process: \(error.localizedDescription)", -1)
    }

    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return (output, task.terminationStatus)
  }

  private func isElevated() -> Bool {
    return getuid() == 0
  }
}
