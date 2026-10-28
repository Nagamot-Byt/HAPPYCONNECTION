class ConnectionProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String domain;
  final String quality;
  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 3389,
    this.username = '',
    this.domain = '',
    this.quality = 'balanced',
  });
}
