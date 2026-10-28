enum RdpSessionState {
  disconnected,
  connecting,
  negotiating,
  active,
  reconnecting,
  failed,
}

class RdpSessionEvent {
  final RdpSessionState state;
  final String? message;
  const RdpSessionEvent(this.state, [this.message]);
}
