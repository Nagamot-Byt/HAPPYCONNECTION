import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';

class ConnectionActionButtons extends StatelessWidget {
  final HomeController controller;

  const ConnectionActionButtons({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.spaceEvenly,
      children: [
        FilledButton.tonalIcon(
          onPressed: controller.busy || !controller.loaded
              ? null
              : controller.runDiagnostics,
          icon: const Icon(Icons.network_check),
          label: Text(AppLocalizations.of(context)!.diagnoseConnection),
        ),
        FilledButton.tonalIcon(
          onPressed: controller.busy || !controller.loaded
              ? null
              : controller.runConnectionTroubleshooter,
          icon: const Icon(Icons.medical_services_outlined),
          label: Text(AppLocalizations.of(context)!.helpMeFix),
        ),
        FilledButton.icon(
          onPressed:
              controller.busy || !controller.loaded ? null : controller.connect,
          icon: controller.busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.play_arrow),
          label: Text(AppLocalizations.of(context)!.connectAndLaunchRdp),
        ),
        OutlinedButton.icon(
          onPressed: (controller.busy ||
                  !controller.loaded ||
                  !controller.splitTunnelActive)
              ? null
              : controller.disconnect,
          icon: const Icon(Icons.stop),
          label: Text(AppLocalizations.of(context)!.disconnectTunnel),
        ),
      ],
    );
  }
}
