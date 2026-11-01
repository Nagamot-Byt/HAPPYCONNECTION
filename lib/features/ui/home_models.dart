class ServerPreset {
  final String id;
  final String label;
  final String host;
  final int port;

  const ServerPreset({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
  });

  bool get isConfigured => host.isNotEmpty && host != 'pendiente';
}

class ConnectionLogEntry {
  final DateTime timestamp;
  final String message;
  final bool isError;

  const ConnectionLogEntry({
    required this.timestamp,
    required this.message,
    required this.isError,
  });

  String get time =>
      timestamp.toIso8601String().split('T').last.substring(0, 12);

  String get formatted => '[$time] $message';
}

class ConnectionLogStore {
  ConnectionLogStore({
    this.maxEntries = 500,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxEntries;
  final DateTime Function() _clock;
  final List<ConnectionLogEntry> _entries = [];

  List<ConnectionLogEntry> get entries => List.unmodifiable(_entries);

  List<String> get formatted =>
      List.unmodifiable(_entries.map((entry) => entry.formatted));

  void add(String message, {bool isError = false}) {
    _entries.add(ConnectionLogEntry(
      timestamp: _clock(),
      message: message,
      isError: isError,
    ));
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  void clear() {
    _entries.clear();
  }
}
