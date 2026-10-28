import 'dart:async';
import '../domain/connection_profile.dart';
import 'session_events.dart';

abstract class RdpEngineProxy {
  Stream<RdpSessionEvent> get events;
  Future<void> connect(ConnectionProfile profile);
  Future<void> disconnect();
  Future<void> sendMouse(int x, int y, int flags);
  Future<void> sendKey(int scancode, int flags);
  Future<int?> registerTexture();
  void setSurface(Object? surface);
}

class InMemoryRdpEngineProxy implements RdpEngineProxy {
  final _controller = StreamController<RdpSessionEvent>.broadcast();
  @override
  Stream<RdpSessionEvent> get events => _controller.stream;

  @override
  Future<void> connect(ConnectionProfile profile) async {
    _controller.add(const RdpSessionEvent(RdpSessionState.connecting));
    await Future.delayed(const Duration(milliseconds: 200));
    _controller.add(const RdpSessionEvent(RdpSessionState.negotiating));
    await Future.delayed(const Duration(milliseconds: 200));
    _controller.add(const RdpSessionEvent(RdpSessionState.active));
  }

  @override
  Future<void> disconnect() async {
    _controller.add(const RdpSessionEvent(RdpSessionState.disconnected));
  }

  @override
  Future<void> sendMouse(int x, int y, int flags) async {}
  @override
  Future<void> sendKey(int scancode, int flags) async {}
  @override
  Future<int?> registerTexture() async => null;
  @override
  void setSurface(Object? surface) {}
}
