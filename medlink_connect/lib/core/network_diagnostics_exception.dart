/// Typed exception for network diagnostics failures.
///
/// Carries a [code] so callers can distinguish between "command not found",
/// "no permission", "timeout", and "unknown" failures without string-matching.
class NetworkDiagnosticsException implements Exception {
  /// Machine-readable error code.
  final NetworkDiagnosticsErrorCode code;

  /// Human-readable description (English for logging; UI can localize).
  final String message;

  /// Optional underlying error for debugging.
  final Object? cause;

  const NetworkDiagnosticsException(
    this.code, {
    required this.message,
    this.cause,
  });

  /// `true` if the operation requires elevation and the current process
  /// is not running as root / Administrator.
  bool get needsElevation => code == NetworkDiagnosticsErrorCode.elevationRequired;

  @override
  String toString() =>
      'NetworkDiagnosticsException(${code.name}): $message${cause != null ? " ($cause)" : ""}';
}

/// Enumerates the known failure modes for network diagnostic operations.
enum NetworkDiagnosticsErrorCode {
  /// The platform command (e.g. `ipconfig`, `systemd-resolve`) was not found.
  commandNotFound,

  /// The operation requires elevated privileges that are not available.
  elevationRequired,

  /// The command timed out.
  timeout,

  /// A general / unexpected platform error occurred.
  platformError,

  /// The operation is not supported on this platform.
  unsupported,
}
