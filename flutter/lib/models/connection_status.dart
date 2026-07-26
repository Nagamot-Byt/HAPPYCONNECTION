class ConnectionStatus {
  final String status;
  final DateTime timestamp;
  final int latencyMs;
  final bool hisNetwork;
  final bool wifiNetwork;

  ConnectionStatus({
    required this.status,
    required this.timestamp,
    required this.latencyMs,
    required this.hisNetwork,
    required this.wifiNetwork,
  });

  factory ConnectionStatus.fromJson(Map<String, dynamic> json) {
    return ConnectionStatus(
      status: json['status'],
      timestamp: DateTime.parse(json['timestamp']),
      latencyMs: json['latency_ms'],
      hisNetwork: json['his_network'],
      wifiNetwork: json['wifi_network'],
    );
  }
}
