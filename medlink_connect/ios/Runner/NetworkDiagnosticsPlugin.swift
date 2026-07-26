import Flutter
import Network
import Darwin

public class NetworkDiagnosticsPlugin: NSObject, FlutterPlugin {
  public static func dummy(methodCall: FlutterMethodCall, result: @escaping FlutterResult) {
    // This method is intentionally empty.
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.medlinkconnect/network_diagnostics",
      binaryMessenger: registrar.messenger())
    let instance = NetworkDiagnosticsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func dummyMethodToEnforceBundling() {
    // This method is intentionally empty.
  }

  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return true
  }
}
