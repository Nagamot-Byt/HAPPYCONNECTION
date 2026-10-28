import 'package:injectable/injectable.dart';
import 'package:flutter/services.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/core/wifi_manager.dart';

/// Default [WifiManager] implementation backed by a native method channel.
@LazySingleton(as: WifiManager)
class DefaultWifiManager implements WifiManager {
  static const _channel = MethodChannel('com.medlinkconnect/wifi_manager');

  @override
  Future<List<String>> scanNetworks() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('scanNetworks');
      return (result ?? <dynamic>[]).cast<String>();
    } on MissingPluginException {
      throw Exception(
          'Wi-Fi automático no está disponible en esta plataforma.');
    } on PlatformException catch (e) {
      throw WifiConnectionException(
          'Error listando redes Wi-Fi (${e.code}): ${e.message}');
    }
  }

  @override
  Future<String> connect({
    required String ssid,
    String? password,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('connect', {
        'ssid': ssid,
        'password': password,
      });
      return result ?? 'Solicitud de conexión Wi-Fi enviada.';
    } on MissingPluginException {
      throw Exception(
          'Wi-Fi automático no está disponible en esta plataforma.');
    } on PlatformException catch (e) {
      throw WifiConnectionException(
          'Error conectando Wi-Fi (${e.code}): ${e.message}');
    }
  }

  @override
  Future<WifiConnectionInfo> getCurrentConnectionInfo() async {
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getCurrentInfo');
      final map = (result ?? <dynamic, dynamic>{}).cast<dynamic, dynamic>();
      return WifiConnectionInfo(
        ssid: (map['ssid'] as String?) ?? '',
        interfaceName: (map['interfaceName'] as String?) ?? '',
        gateway: (map['gateway'] as String?) ?? '',
      );
    } on MissingPluginException {
      throw Exception(
          'Wi-Fi automático no está disponible en esta plataforma.');
    } on PlatformException catch (e) {
      throw WifiConnectionException(
        'Error consultando Wi-Fi actual (${e.code}): ${e.message}',
      );
    }
  }
}
