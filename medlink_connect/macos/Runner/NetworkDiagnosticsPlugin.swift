import FlutterMacOS
import Network
import Darwin

public class NetworkDiagnosticsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.medlinkconnect/network_diagnostics",
      binaryMessenger: registrar.messenger())
    let instance = NetworkDiagnosticsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func dummyMethodToEnforceBundling() {
    // Enforce bundling
  }

  public func methodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "flushDns":
      flushDns(result: result)
    case "clearNetworkCaches":
      clearNetworkCaches(result: result)
    case "ping":
      if let args = call.arguments as? [String: Any],
         let host = args["host"] as? String {
        ping(host: host, result: result)
      } else {
        result(FlutterError(code: "invalid_args", message: "Missing host", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func flushDns(result: @escaping FlutterResult) {
    // macOS DNS flush via mDNSResponder
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
    process.arguments = ["-flushcache"]
    do {
      try process.run()
      process.waitUntilExit()
      result(process.terminationStatus == 0)
    } catch {
      result(false)
    }
  }

  private func clearNetworkCaches(result: @escaping FlutterResult) {
    // Clear ARP cache
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/sbin/arp")
    process.arguments = ["-ad"]
    do {
      try process.run()
      process.waitUntilExit()
      result(process.terminationStatus == 0)
    } catch {
      result(false)
    }
  }

  private func ping(host: String, result: @escaping FlutterResult) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/sbin/ping")
    process.arguments = ["-c", "4", "-W", "2000", host]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
      try process.run()
      process.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        if let avgRtt = parseAverageRtt(from: output) {
          result(avgRtt)
        } else {
          result(-1)
        }
      } else {
        result(-1)
      }
    } catch {
      result(-1)
    }
  }

  private func parseAverageRtt(from output: String) -> Int? {
    let pattern = "rtt min/avg/max/stddev = [0-9.]+/([0-9.]+)/[0-9.]+/[0-9.]+"
    if let regex = try? NSRegularExpression(pattern: pattern) {
      let range = NSRange(output.startIndex..<output.endIndex, in: output)
      if let match = regex.firstMatch(in: output, range: range),
         let matchRange = Range(match.range(at: 1), in: output) {
        if let avg = Double(String(output[matchRange])) {
          return Int(avg.rounded())
        }
      }
    }
    return nil
  }
}
