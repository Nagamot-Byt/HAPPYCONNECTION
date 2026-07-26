import FlutterMacOS

public class RouteManagerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.medlinkconnect/route_manager",
      binaryMessenger: registrar.messenger())
    let instance = RouteManagerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private var trackedRoutes: [String] = []

  public func dummyMethodToEnforceBundling() {}

  public func methodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "addRoute":
      if let args = call.arguments as? [String: Any] {
        addRoute(args: args, result: result)
      }
    case "removeRoute":
      if let args = call.arguments as? [String: Any] {
        removeRoute(args: args, result: result)
      }
    case "enableSplitTunnel":
      if let args = call.arguments as? [String: Any] {
        enableSplitTunnel(args: args, result: result)
      }
    case "disableSplitTunnel":
      disableSplitTunnel(result: result)
    case "getTrackedRoutes":
      result(trackedRoutes)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func addRoute(args: [String: Any], result: @escaping FlutterResult) {
    guard let dest = args["destinationCidr"] as? String,
          let gateway = args["gateway"] as? String else {
      result(false)
      return
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/sbin/route")
    process.arguments = ["add", "-net", dest, gateway]

    do {
      try process.run()
      process.waitUntilExit()
      result(process.terminationStatus == 0)
    } catch {
      result(false)
    }
  }

  private func removeRoute(args: [String: Any], result: @escaping FlutterResult) {
    guard let dest = args["destinationCidr"] as? String else {
      result(false)
      return
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/sbin/route")
    process.arguments = ["delete", "-net", dest]

    do {
      try process.run()
      process.waitUntilExit()
      result(process.terminationStatus == 0)
    } catch {
      result(false)
    }
  }

  private func enableSplitTunnel(args: [String: Any], result: @escaping FlutterResult) {
    guard let subnets = args["hospitalSubnets"] as? [String],
          let gateway = args["gateway"] as? String else {
      result(["success": false, "message": "Invalid arguments"])
      return
    }

    trackedRoutes.removeAll()
    for subnet in subnets {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/sbin/route")
      process.arguments = ["add", "-net", subnet, gateway]

      do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
          trackedRoutes.append(subnet)
        }
      } catch {
        // Rollback
        for tracked in trackedRoutes {
          let rollback = Process()
          rollback.executableURL = URL(fileURLWithPath: "/sbin/route")
          rollback.arguments = ["delete", "-net", tracked]
          try? rollback.run()
        }
        result(["success": false, "message": "Failed to enable split tunnel"])
        return
      }
    }

    result([
      "success": true,
      "message": "Split tunnel enabled",
      "affectedRoutes": trackedRoutes
    ])
  }

  private func disableSplitTunnel(result: @escaping FlutterResult) {
    for route in trackedRoutes {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/sbin/route")
      process.arguments = ["delete", "-net", route]
      try? process.run()
    }
    trackedRoutes.removeAll()
    result(["success": true, "message": "Split tunnel disabled"])
  }
}
