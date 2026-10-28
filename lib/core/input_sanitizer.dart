/// Centralized input validation for all values that flow to native platform
/// commands (PowerShell, cmd). Prevents command injection attacks.
abstract final class InputSanitizer {
  // Regex for valid IPv4: e.g., 192.168.1.1
  static final _ipv4Pattern =
      RegExp(r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)(\.(?!$)|$)){4}$');

  // Regex for hostname: letters, digits, dots, hyphens, underscores only
  static final _hostnamePattern =
      RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,253}[a-zA-Z0-9]$');

  // Regex for interface names: letters, digits, spaces, hyphens, underscores
  static final _interfacePattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9 _-]{0,63}$');

  // Dangerous shell metacharacters
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
  static String sanitizeInterfaceName(String input,
      {String fieldName = 'Interfaz'}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El campo no puede estar vacío.');
    }
    if (_shellMetaChars.hasMatch(trimmed)) {
      throw ArgumentError.value(
          trimmed, fieldName, 'Contiene caracteres no permitidos.');
    }
    if (!_interfacePattern.hasMatch(trimmed)) {
      throw ArgumentError.value(
          trimmed, fieldName, 'Nombre de interfaz inválido.');
    }
    return trimmed;
  }

  /// Validates and returns a sanitized Wi-Fi SSID.
  /// SSIDs can contain most printable characters but we strip shell dangers.
  static String sanitizeSsid(String input, {String fieldName = 'SSID'}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El campo no puede estar vacío.');
    }
    if (_shellMetaChars.hasMatch(trimmed)) {
      throw ArgumentError.value(trimmed, fieldName,
          'El SSID contiene caracteres no seguros para operaciones del sistema.');
    }
    if (trimmed.length > 32) {
      throw ArgumentError.value(
          trimmed, fieldName, 'El SSID no puede tener más de 32 caracteres.');
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
