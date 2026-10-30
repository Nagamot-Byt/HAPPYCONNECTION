import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/features/ui/widgets/glass_container.dart';

class NetworkDiagnosticsView extends StatefulWidget {
  const NetworkDiagnosticsView({super.key});

  @override
  State<NetworkDiagnosticsView> createState() => _NetworkDiagnosticsViewState();
}

class _NetworkDiagnosticsViewState extends State<NetworkDiagnosticsView> {
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        GlassContainer(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.wifiSectionTitle,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  controller.wifiManager == null
                      ? l10n.wifiNoNativeHelper
                      : l10n.wifiSelectHint,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (controller.wifiManager != null) ...[
                  _buildWifiSelector(context, controller),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TextField(
                      controller: controller.wifiPasswordCtrl,
                      enabled: !controller.busy,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.wifiPassword,
                        hintText: l10n.wifiPasswordHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ] else
                  Text(
                    l10n.wifiNoHelperTip,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: controller.busy ||
                              !controller.loaded ||
                              controller.wifiManager == null
                          ? null
                          : () => controller.refreshWifiNetworks(),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.refreshNetworks),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: controller.busy ||
                              !controller.loaded ||
                              controller.wifiManager == null
                          ? null
                          : () => controller.connectWifiOnly(),
                      icon: const Icon(Icons.wifi),
                      label: Text(l10n.connectWifi),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer(
          child: ExpansionTile(
            initiallyExpanded: _showAdvanced,
            onExpansionChanged: (value) =>
                setState(() => _showAdvanced = value),
            title: Text(l10n.advancedOptions),
            subtitle: Text(l10n.advancedOptionsSubtitle),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.advancedValuesHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: controller.busy ||
                          !controller.loaded ||
                          controller.wifiManager == null
                      ? null
                      : () => controller.syncCurrentWifiInfo(silent: false),
                  icon: const Icon(Icons.my_location_outlined),
                  label: Text(l10n.detectCurrentNetwork),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: TextField(
                        controller: controller.gatewayCtrl,
                        enabled: !controller.busy,
                        decoration: InputDecoration(
                          labelText: l10n.gateway,
                          hintText: l10n.gatewayHint,
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
                        controller: controller.ifaceCtrl,
                        enabled: !controller.busy,
                        decoration: InputDecoration(
                          labelText: l10n.networkInterface,
                          hintText: l10n.interfaceHint,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: TextField(
                  controller: controller.subnetsCtrl,
                  enabled: !controller.busy,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.hospitalSubnetsOnePerLine,
                    hintText: l10n.hospitalSubnetsHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWifiSelector(BuildContext context, HomeController controller) {
    final l10n = AppLocalizations.of(context)!;
    final options = <String>[
      ...controller.wifiNetworks.where((e) => e.isNotEmpty),
    ];

    if (controller.selectedWifiSsid != null &&
        controller.selectedWifiSsid != controller.manualWifiOption &&
        !controller.wifiNetworks.contains(controller.selectedWifiSsid)) {
      options.insert(0, controller.selectedWifiSsid!);
    }

    final dropdownItems = <DropdownMenuItem<String>>[
      for (final ssid in options)
        DropdownMenuItem<String>(
          value: ssid,
          child: Text(ssid),
        ),
      DropdownMenuItem<String>(
        value: controller.manualWifiOption,
        child: Text(l10n.otherNetwork),
      ),
    ];

    final value = (() {
      final selected = controller.selectedWifiSsid;
      if (selected == null || selected.isEmpty) return null;
      if (selected == controller.manualWifiOption) {
        return controller.manualWifiOption;
      }
      return options.contains(selected)
          ? selected
          : controller.manualWifiOption;
    })();

    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.wifiNetworkLabel,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: controller.wifiNetworksLoading
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          items: dropdownItems,
          onChanged: controller.busy
              ? null
              : (val) {
                  controller.selectedWifiSsid = val;
                  if (val != null && val != controller.manualWifiOption) {
                    controller.manualWifiCtrl.text = val;
                  }
                },
        ),
        const SizedBox(height: 12),
        if (controller.selectedWifiSsid == controller.manualWifiOption ||
            controller.wifiNetworks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: TextField(
              controller: controller.manualWifiCtrl,
              enabled: !controller.busy,
              decoration: InputDecoration(
                labelText: l10n.wifiNetworkName,
                hintText: l10n.wifiNetworkNameHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
      ],
    );
  }
}
