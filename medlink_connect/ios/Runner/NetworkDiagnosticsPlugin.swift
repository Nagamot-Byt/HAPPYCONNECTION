import Flutter
import UIKit
import Network

/// iOS implementation of the `com.medlinkconnect/network_diagnostics`
/// method channel.
///
/// **DNS flush / cache clear:** These are no-ops on iOS because the OS
/// sandboxes apps from manipulating system-level DNS and ARP caches.
/// The methods always return `true` to indicate "no action needed".
///
/// **Ping:** ICMP is not available to iOS apps. Instead, we perform a
/// TCP connect to the target host on port 3389 (RDP) and measure the
/// connection time. Falls back to DNS resolution time if TCP fails.
public class NetworkDiagnosticsPlugin: NSObject, FlutterPlugin {

  private static let defaultPort: UInt16 = 3389

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.medlinkconnect/network_diagnostics",
      binaryMessenger: registrar.messenger())
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

  // MARK: - DNS flush

  private func handleFlushDns(result: @escaping FlutterResult) {
    // iOS sandboxes apps — cannot flush system DNS cache.
    NSLog("[NetworkDiagnosticsPlugin] flushDns: no-op on iOS (sandboxed)")
    result(true)
  }

  // MARK: - Cache clear

  private func handleClearCaches(result: @escaping FlutterResult) {
    NSLog("[NetworkDiagnosticsPlugin] clearNetworkCaches: no-op on iOS (sandboxed)")
    result(true)
  }

  // MARK: - Ping (TCP connect proxy)

  private func handlePing(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "bad_arguments",
                          message: "Expected a map with 'host', 'count', 'timeoutMs'.",
                          details: nil))
      return
    }

    let host = args["host"] as? String ?? "8.8.8.8"
    let count = args["count"] as? Int ?? 4
    let timeoutMs = args["timeoutMs"] as? Int ?? 2000
    let port = args["port"] as? UInt16 ?? Self.defaultPort

    // Use NWConnection (Network.framework) for TCP connect measurement
    let group = DispatchGroup()
    var latencies: [Int] = []
    let queue = DispatchQueue(label: "com.medlinkconnect.ping", qos: .default)

    for _ in 0..<count {
      group.enter()
      let start = DispatchTime.now()

      let endpoint = NWEndpoint.hostPort(
        host: NWEndpoint.Host(host),
        port: NWEndpoint.Port(rawValue: port)!)
      let connection = NWConnection(to: endpoint, using: .tcp)

      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
          latencies.append(Int(elapsed / 1_000_000))  // ns → ms
          connection.cancel()
          group.leave()
        case .failed, .cancelled:
          connection.cancel()
          group.leave()
        default:
          break
        }
      }

      connection.start(queue: queue)

      // Timeout
      let timeout = DispatchTime.now() + .milliseconds(timeoutMs)
      _ = group.wait(timeout: timeout)
    }

    // Wait for remaining callbacks (up to 500ms extra)
    _ = group.wait(timeout: .now() + .milliseconds(500))

    if !latencies.isEmpty {
      let avgMs = latencies.reduce(0, +) / latencies.count
      result(avgMs)
    } else {
      // Fallback: DNS resolution time
      let dnsStart = DispatchTime.now()
      let dnsHost = CFHostCreateWithName(nil, host as CFString)
      if let dnsHost = dnsHost {
        var resolved = DarwinBoolean(false)
        CFHostStartInfoResolution(dnsHost, .addresses, nil)
        // Quick synchronous attempt
        if let addresses = CFHostGetAddressing(dnsHost, &resolved) as? [Data], !addresses.isEmpty {
          let dnsElapsed = DispatchTime.now().uptimeNanoseconds - dnsStart.uptimeNanoseconds
          let dnsMs = Int(dnsElapsed / 1_000_000)
          NSLog("[NetworkDiagnosticsPlugin] ping: TCP connect failed but DNS resolved in \(dnsMs)ms")
          result(dnsMs)
          return
        }
      }

      NSLog("[NetworkDiagnosticsPlugin] ping: host \(host) unreachable via TCP:\(port) and DNS")
      result(nil)
    }
  }
}
