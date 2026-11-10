import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/features/ui/home_models.dart';

/// Catálogo, selección y diagnóstico de latencia de los presets de servidor
/// hospitalario expuestos por [HomeController].
class ServerPresetSelector {
  ServerPresetSelector({
    required this.networkDiagnostics,
    required this.l10n,
    required this.onLog,
    required this.onApply,
  });

  final NetworkDiagnostics networkDiagnostics;
  final AppLocalizations l10n;
  final void Function(String message, {bool isError}) onLog;
  final void Function(ServerPreset preset) onApply;

  static List<ServerPreset> hospitalCatalog(AppLocalizations l10n) => [
        ServerPreset(
            id: 'pediatrico',
            label: l10n.presetPediatric,
            host: 'serv_pediatrico.huv.gov.co',
            port: 3389),
        ServerPreset(
            id: 'ginecologico',
            label: l10n.presetGynecology,
            host: 'serv_ginecologico.huv.gov.co',
            port: 3389),
        ServerPreset(
            id: 'moviles',
            label: l10n.presetMobile,
            host: 'serv_moviles.huv.gov.co',
            port: 3389),
        ServerPreset(
            id: 'consulta_externa',
            label: l10n.presetOutpatient,
            host: 'serv_const_ext.huv.gov.co',
            port: 3389),
        ServerPreset(
            id: 'urgencias',
            label: l10n.presetEmergency,
            host: 'serv_urgencias.huv.gov.co',
            port: 3389),
      ];

  List<ServerPreset> _presets = [];
  List<ServerPreset> get presets => List.unmodifiable(_presets);
  set presets(List<ServerPreset> value) {
    _presets = List.from(value);
  }

  String selectedPresetId = 'manual';

  void keepSelectionValid() {
    if (selectedPresetId != 'manual' &&
        !_presets.any((p) => p.id == selectedPresetId)) {
      selectedPresetId = 'manual';
    }
  }

  ServerPreset? presetById(String id) {
    for (final preset in _presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  void applyPreset(ServerPreset preset) {
    onApply(preset);
    selectedPresetId = preset.id;
  }

  Future<ServerPreset?> diagnoseBest({bool apply = true}) async {
    if (_presets.isEmpty) return null;
    onLog(l10n.logDiagnosingBestServer, isError: false);
    final responses = <MapEntry<ServerPreset, int>>[];
    // Los cinco destinos se prueban en paralelo para no encadenar sus tiempos
    // de espera; se conserva el de menor latencia TCP.
    await Future.wait([
      for (final preset in _presets)
        if (preset.isConfigured)
          () async {
            try {
              final result = await measureTcpPortWithRetryDetailed(
                preset.host,
                preset.port,
                label: preset.label,
              );
              final ms = result.latency;
              if (ms != null && ms > 0) {
                onLog(l10n.logServerResponded(preset.label, ms));
                responses.add(MapEntry(preset, ms));
              } else {
                onLog(
                  l10n.logServerNoResponse(
                    preset.label,
                    result.error ?? 'unknown',
                  ),
                );
              }
            } catch (e) {
              onLog(l10n.logServerNoResponse(preset.label, '$e'));
            }
          }(),
    ]);

    ServerPreset? best;
    int? bestMs;
    for (final response in responses) {
      if (bestMs == null || response.value < bestMs) {
        best = response.key;
        bestMs = response.value;
      }
    }
    if (best != null) {
      if (bestMs != null) {
        onLog(l10n.logBestServer(best.label, bestMs));
      }
      if (apply) applyPreset(best);
      return best;
    }
    ServerPreset? fallback;
    for (final preset in _presets) {
      if (preset.isConfigured) {
        fallback = preset;
        break;
      }
    }
    if (fallback == null) {
      onLog(l10n.presetsEmptySubtitle, isError: true);
      return null;
    }
    onLog(
      l10n.logNoServerResponded(fallback.label),
      isError: true,
    );
    if (apply) applyPreset(fallback);
    return fallback;
  }

  Future<({int? latency, String? error})> measureTcpPortWithRetryDetailed(
    String host,
    int port, {
    String? label,
  }) async {
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 350),
      Duration(milliseconds: 700),
    ];

    int? best;
    String? lastError;
    for (var attempt = 0; attempt < delays.length; attempt++) {
      final delay = delays[attempt];
      if (delay > Duration.zero) {
        onLog(
          label == null
              ? l10n.logRetryingTcpNoLabel(attempt, delays.length - 1)
              : l10n.logRetryingTcp(label, attempt, delays.length - 1),
        );
        await Future<void>.delayed(delay);
      }
      final probe = await networkDiagnostics.checkTcpPortDetailed(host, port);
      final latency = probe.value;
      if (latency != null) {
        best = best == null ? latency : (latency < best ? latency : best);
        if (attempt > 0) {
          onLog(l10n.logServerRetrySuccess(attempt + 1));
        }
        break;
      }
      lastError = probe.error;
    }
    return (latency: best, error: best == null ? lastError : null);
  }
}
