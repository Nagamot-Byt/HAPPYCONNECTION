import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/features/ui/widgets/glass_container.dart';

class ServerSelectionPanel extends StatelessWidget {
  const ServerSelectionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    final presets = controller.serverPresets;
    final l10n = AppLocalizations.of(context)!;

    return GlassContainer(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.rdpSectionTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: controller.selectedServerPresetId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.serverPresetLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                DropdownMenuItem(
                  value: 'manual',
                  child: Text(l10n.manual),
                ),
                for (final preset in presets)
                  DropdownMenuItem(
                    value: preset.id,
                    child: Text(
                      preset.isConfigured
                          ? '${preset.label} - ${preset.host}:${preset.port}'
                          : l10n.presetPending(preset.label),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: controller.busy
                  ? null
                  : (value) {
                      if (value == null) return;
                      if (value == 'manual') {
                        controller.selectedServerPresetId = 'manual';
                        return;
                      }
                      final preset = controller.presetById(value);
                      if (preset == null) return;
                      if (!preset.isConfigured) {
                        controller.preferMostStableServer = false;
                        controller.selectedServerPresetId = value;
                        controller.setGuidance(
                          l10n.presetPendingTitle,
                          bullets: [
                            l10n.presetPendingBullet1,
                            l10n.presetPendingBullet2,
                          ],
                          isError: true,
                        );
                        return;
                      }
                      // Elegir un servidor concreto desactiva la selección
                      // automática para respetar la elección del usuario.
                      controller.preferMostStableServer = false;
                      controller.applyServerPreset(preset);
                    },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: controller.preferMostStableServer,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.autoSelectServer),
              subtitle: Text(
                presets.isEmpty
                    ? l10n.presetsEmptySubtitle
                    : l10n.presetsReadySubtitle,
              ),
              onChanged: controller.busy
                  ? null
                  : (value) {
                      controller.preferMostStableServer = value;
                    },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: controller.busy || !controller.loaded
                    ? null
                    : () => controller.diagnoseBestServerPreset(),
                icon: const Icon(Icons.hub_outlined),
                label: Text(l10n.diagnoseBestServer),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TextField(
                      controller: controller.rdpHostCtrl,
                      enabled: !controller.busy,
                      decoration: InputDecoration(
                        labelText: l10n.rdpHostLabel,
                        hintText: l10n.rdpHostHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TextField(
                      controller: controller.rdpPortCtrl,
                      enabled: !controller.busy,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.rdpPortLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TextField(
                      controller: controller.rdpUserCtrl,
                      enabled: !controller.busy,
                      decoration: InputDecoration(
                        labelText: l10n.rdpUserOptional,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TextField(
                      controller: controller.rdpDomainCtrl,
                      enabled: !controller.busy,
                      decoration: InputDecoration(
                        labelText: l10n.rdpDomainOptional,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              value: controller.rdpProfile,
              decoration: InputDecoration(
                labelText: l10n.rdpProfile,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                DropdownMenuItem(
                  value: 'adaptive',
                  child: Text(l10n.profileAdaptive),
                ),
                DropdownMenuItem(
                  value: 'stable',
                  child: Text(l10n.profileStable),
                ),
                DropdownMenuItem(
                  value: 'speed',
                  child: Text(l10n.profileSpeed),
                ),
              ],
              onChanged: controller.busy
                  ? null
                  : (value) {
                      if (value != null) controller.rdpProfile = value;
                    },
            ),
            const SizedBox(height: 12),
            Text(
              l10n.rdpProfileExplanation,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
