import 'dart:io';

/// Centralized input validation for values that flow to native platform APIs.
/// Host/CIDR values still pass through shell-based helpers on some platforms,
/// so they keep a strict allow-list; interface and SSID names only reject
/// control characters (they are passed as arguments, never as shell text).
abstract final class InputSanitizer {
  // Regex for valid IPv4: e.g., 192.168.1.1
  static final _ipv4Pattern =
      RegExp(r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)(\.(?!$)|$)){4}$');

  // Regex for hostname: letters, digits, dots, hyphens, underscores only
  static final _hostnamePattern =
      RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,253}[a-zA-Z0-9]$');

  // Control characters are never valid in names sent to native APIs.
  static final _controlChars = RegExp(r'[\x00-\x1F\x7F]');

  // Android and macOS native validators only accept this subset.
  static final _strictInterfacePattern = RegExp(r'^[A-Za-z0-9_.:-]+$');

  // Dangerous shell metacharacters (hostnames still flow to OS commands).
  static final _shellMetaChars = RegExp(r'[;&|`$(){}\[\]<>!\\\n\r]');

  /// Validates and returns a sanitized IPv4 address.
  /// Throws [ArgumentError] if the input contains non-IP characters or
  /// does not match the IPv4 pattern.
  static String sanitizeIpv4(String input, {String fieldName = 'IP'}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El campo no puede estar vacío.');
    }
    if (_shellMetaChars.hasMatch(trimmed)) {
      throw ArgumentError.value(
          trimmed, fieldName, 'Contiene caracteres no permitidos.');
    }
    if (!_ipv4Pattern.hasMatch(trimmed)) {
      throw ArgumentError.value(
          trimmed, fieldName, 'No es una dirección IPv4 válida.');
    }
    return trimmed;
  }

  /// Validates and returns a sanitized CIDR notation (e.g., 10.0.0.0/8).
  static String sanitizeCidr(String input, {String fieldName = 'CIDR'}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El campo no puede estar vacío.');
    }
    if (_shellMetaChars.hasMatch(trimmed)) {
      throw ArgumentError.value(
          trimmed, fieldName, 'Contiene caracteres no permitidos.');
    }
    final parts = trimmed.split('/');
    if (parts.length == 1) {
      // Plain IP without prefix — validate as IP
      return sanitizeIpv4(trimmed, fieldName: fieldName);
    }
    if (parts.length != 2) {
      throw ArgumentError.value(trimmed, fieldName, 'Formato CIDR inválido.');
    }
    sanitizeIpv4(parts[0], fieldName: '$fieldName (IP)');
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) {
      throw ArgumentError.value(
          trimmed, fieldName, 'Prefijo CIDR debe estar entre 0 y 32.');
    }
    return trimmed;
  }

  /// Validates and returns a sanitized hostname or IP.
  /// Accepts both IPv4 addresses and DNS hostnames.
  static String sanitizeHostname(String input, {String fieldName = 'Host'}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El campo no puede estar vacío.');
    }
    if (_shellMetaChars.hasMatch(trimmed)) {
      throw ArgumentError.value(
          trimmed, fieldName, 'Contiene caracteres no permitidos.');
    }
    // Try as IPv4 first
    if (_ipv4Pattern.hasMatch(trimmed)) return trimmed;
    // Then as hostname
    if (!_hostnamePattern.hasMatch(trimmed)) {
      throw ArgumentError.value(trimmed, fieldName,
          'Nombre de host inválido. Solo letras, números, puntos y guiones.');
    }
    return trimmed;
  }

  /// Validates and returns a sanitized network interface name.
  ///
  /// Windows interface aliases may contain spaces or parentheses, such as
  /// `vEthernet (Default Switch)`. Android and macOS only accept the stricter
  /// `[A-Za-z0-9_.:-]` subset, so [android] can be forced in tests or callers.
  static String sanitizeInterfaceName(String input,
      {String fieldName = 'Interfaz', bool? android}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El campo no puede estar vacío.');
    }
    if (_controlChars.hasMatch(trimmed)) {
      throw ArgumentError.value(
          trimmed, fieldName, 'Contiene caracteres de control no permitidos.');
    }
    if (trimmed.length > 128) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El nombre de interfaz es demasiado largo.');
    }
    if ((android ?? (Platform.isAndroid || Platform.isMacOS)) &&
        !_strictInterfacePattern.hasMatch(trimmed)) {
      throw ArgumentError.value(
          trimmed,
          fieldName,
          'En Android y macOS solo se permiten letras, números, punto, '
          'guion, guion bajo y dos puntos.');
    }
    return trimmed;
  }

  /// Validates and returns a sanitized Wi-Fi SSID.
  /// SSIDs can contain most printable characters (including `&` or `()`).
  static String sanitizeSsid(String input, {String fieldName = 'SSID'}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El campo no puede estar vacío.');
    }
    if (_controlChars.hasMatch(trimmed)) {
      throw ArgumentError.value(trimmed, fieldName,
          'El SSID contiene caracteres de control no permitidos.');
    }
    if (trimmed.length > 32) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El SSID no puede tener más de 32 caracteres.');
    }
    return trimmed;
  }

  /// Validates an RDP username or domain. Newlines and control characters
  /// are rejected to prevent injection into generated `.rdp` files.
  static String sanitizeRdpCredential(String input,
      {String fieldName = 'Credencial RDP'}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El campo no puede estar vacío.');
    }
    if (_controlChars.hasMatch(trimmed)) {
      throw ArgumentError.value(
          trimmed, fieldName, 'Contiene caracteres de control no permitidos.');
    }
    if (trimmed.length > 256) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El valor es demasiado largo.');
    }
    return trimmed;
  }

  /// Validates and returns a sanitized TCP port number.
  static int sanitizePort(String input, {String fieldName = 'Puerto'}) {
    final trimmed = input.trim();
    if (_shellMetaChars.hasMatch(trimmed)) {
      throw ArgumentError.value(
          trimmed, fieldName, 'Contiene caracteres no permitidos.');
    }
    final port = int.tryParse(trimmed);
    if (port == null || port <= 0 || port > 65535) {
      throw ArgumentError.value(trimmed, fieldName,
          'Puerto inválido. Debe ser un número entre 1 y 65535.');
    }
    return port;
  }

  /// Validates a list of subnet strings. Returns a sanitized list.
  static List<String> sanitizeSubnets(List<String> subnets,
      {String fieldName = 'Subredes'}) {
    if (subnets.isEmpty) {
      throw ArgumentError.value(
          subnets, fieldName, 'Debe haber al menos una subred.');
    }
    return subnets
        .map((s) => sanitizeCidr(s, fieldName: fieldName))
        .toList(growable: false);
  }
}
