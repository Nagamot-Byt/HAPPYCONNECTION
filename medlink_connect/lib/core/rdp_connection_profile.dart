import 'dart:convert';

/// Persistent configuration for an RDP connection target.
///
/// Designed to be serialized to/from JSON so consuming code can store
/// profiles in [SharedPreferences], a local file, or any key-value store.
///
/// Example:
/// ```dart
/// final profile = RdpConnectionProfile(
///   name: 'Servidor Ginecología',
///   address: '10.0.0.100',
///   port: 3389,
///   username: 'dr.garcia',
/// );
/// final json = jsonEncode(profile.toJson());
/// // Persist json...
/// final restored = RdpConnectionProfile.fromJson(jsonDecode(json));
/// ```
class RdpConnectionProfile {
  /// Human-readable label shown in the UI (e.g. "Servidor Ginecología").
  String name;

  /// Target hostname or IP address (IPv4, IPv6, or FQDN).
  String address;

  /// RDP port — almost always 3389.
  int port;

  /// Optional pre-filled username for the Windows login screen.
  String? username;

  RdpConnectionProfile({
    required this.name,
    required this.address,
    this.port = 3389,
    this.username,
  });

  // ---- Validation ----

  /// Returns `null` if the profile is valid, or a Spanish error string
  /// describing the problem.
  String? validate() {
    if (name.trim().isEmpty) return 'El nombre del perfil es obligatorio.';
    if (address.trim().isEmpty) return 'La dirección del servidor es obligatoria.';
    if (port <= 0 || port > 65535) return 'El puerto debe estar entre 1 y 65535.';
    return null;
  }

  /// Whether this profile passes [validate].
  bool get isValid => validate() == null;

  // ---- JSON serialization ----

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'port': port,
        if (username != null) 'username': username,
      };

  factory RdpConnectionProfile.fromJson(Map<String, dynamic> json) {
    return RdpConnectionProfile(
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 3389,
      username: json['username'] as String?,
    );
  }

  /// Convenience: encode a list of profiles to a JSON string.
  static String listToJson(List<RdpConnectionProfile> profiles) =>
      jsonEncode(profiles.map((p) => p.toJson()).toList());

  /// Convenience: decode a list of profiles from a JSON string.
  static List<RdpConnectionProfile> listFromJson(String jsonStr) {
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => RdpConnectionProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Copy & equality ----

  RdpConnectionProfile copyWith({
    String? name,
    String? address,
    int? port,
    String? username,
    bool clearUsername = false,
  }) {
    return RdpConnectionProfile(
      name: name ?? this.name,
      address: address ?? this.address,
      port: port ?? this.port,
      username: clearUsername ? null : username ?? this.username,
    );
  }

  @override
  String toString() =>
      'RdpConnectionProfile(name: $name, address: $address, '
      'port: $port, username: ${username ?? '(none)'})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RdpConnectionProfile &&
          name == other.name &&
          address == other.address &&
          port == other.port &&
          username == other.username;

  @override
  int get hashCode => Object.hash(name, address, port, username);
}
