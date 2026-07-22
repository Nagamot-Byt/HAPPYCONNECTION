/// Structured result from an RDP launch attempt.
///
/// Provides a Spanish-language message suitable for direct display to
/// clinicians, plus an optional machine-readable [errorCode] for logging
/// and support-ticket correlation.
class RdpLaunchResult {
  /// Whether the RDP client was launched successfully.
  final bool success;

  /// Spanish-language human-readable message (e.g. "✅ Conectado").
  final String message;

  /// Machine-readable error code for diagnostics (e.g. "RDP_CLIENT_NOT_FOUND").
  final String? errorCode;

  const RdpLaunchResult({
    required this.success,
    required this.message,
    this.errorCode,
  });

  // ---- Named constructors for common outcomes ----

  /// Success: the RDP client accepted the launch.
  factory RdpLaunchResult.connected() => const RdpLaunchResult(
        success: true,
        message: '✅ Conectado',
      );

  /// No compatible RDP client was detected on this device.
  factory RdpLaunchResult.clientNotFound() => const RdpLaunchResult(
        success: false,
        message:
            '⚠ Cliente RDP no encontrado.\nInstale Microsoft Remote Desktop '
            'desde la tienda de aplicaciones.',
        errorCode: 'RDP_CLIENT_NOT_FOUND',
      );

  /// The RDP client was found but the URI failed to launch.
  factory RdpLaunchResult.launchFailed(String detail) => RdpLaunchResult(
        success: false,
        message: '❌ Error al iniciar la sesión RDP: $detail',
        errorCode: 'RDP_LAUNCH_FAILED',
      );

  /// The connection profile is missing required fields or is malformed.
  factory RdpLaunchResult.invalidConfiguration(String detail) =>
      RdpLaunchResult(
        success: false,
        message: '⚠ Configuración de conexión inválida: $detail',
        errorCode: 'RDP_INVALID_CONFIG',
      );

  /// The pre-launch platform hook vetoed the connection.
  factory RdpLaunchResult.preLaunchDenied(String? reason) => RdpLaunchResult(
        success: false,
        message: reason ?? '⚠ La conexión fue rechazada por el sistema.',
        errorCode: 'RDP_PRELAUNCH_DENIED',
      );

  @override
  String toString() =>
      'RdpLaunchResult(success: $success, message: $message, '
      'errorCode: $errorCode)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RdpLaunchResult &&
          success == other.success &&
          message == other.message &&
          errorCode == other.errorCode;

  @override
  int get hashCode => Object.hash(success, message, errorCode);
}
