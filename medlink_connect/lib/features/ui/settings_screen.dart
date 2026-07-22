import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences keys used to persist settings.
class _SettingKeys {
  static const hostname = 'settings.server.hostname';
  static const port = 'settings.server.port';
  static const username = 'settings.server.username';
  static const subnets = 'settings.splitTunnel.subnets';
  static const gateway = 'settings.splitTunnel.gateway';
  static const interface = 'settings.splitTunnel.interface';
  static const pingHost = 'settings.diagnostics.pingHost';
  static const pingTimeout = 'settings.diagnostics.pingTimeout';
  static const darkMode = 'settings.appearance.darkMode';
}

/// Full settings page for MedLink Connect.
///
/// All user-visible text is in Spanish as required for the hospital IT staff
/// audience. Settings are persisted via [SharedPreferences] — loaded on init
/// and saved eagerly on every change.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ---- Controllers ----
  final _hostnameCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _gatewayCtrl = TextEditingController();
  final _interfaceCtrl = TextEditingController();
  final _pingHostCtrl = TextEditingController();

  // ---- Subnets ----
  final List<TextEditingController> _subnetCtrls = [];
  final List<FocusNode> _subnetFocusNodes = [];

  // ---- Other state ----
  double _pingTimeout = 3.0;
  bool _darkMode = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _hostnameCtrl.dispose();
    _portCtrl.dispose();
    _usernameCtrl.dispose();
    _gatewayCtrl.dispose();
    _interfaceCtrl.dispose();
    _pingHostCtrl.dispose();
    for (final c in _subnetCtrls) {
      c.dispose();
    }
    for (final f in _subnetFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostnameCtrl.text = prefs.getString(_SettingKeys.hostname) ?? '';
      _portCtrl.text =
          (prefs.getInt(_SettingKeys.port) ?? 3389).toString();
      _usernameCtrl.text = prefs.getString(_SettingKeys.username) ?? '';

      // Subnets
      final rawSubnets = prefs.getStringList(_SettingKeys.subnets) ?? [];
      for (final s in rawSubnets) {
        final ctrl = TextEditingController(text: s);
        _subnetCtrls.add(ctrl);
        _subnetFocusNodes.add(FocusNode());
      }

      _gatewayCtrl.text = prefs.getString(_SettingKeys.gateway) ?? '';
      _interfaceCtrl.text = prefs.getString(_SettingKeys.interface) ?? '';

      _pingHostCtrl.text = prefs.getString(_SettingKeys.pingHost) ?? '8.8.8.8';
      _pingTimeout = prefs.getDouble(_SettingKeys.pingTimeout) ?? 3.0;
      _darkMode = prefs.getBool(_SettingKeys.darkMode) ?? false;
      _loaded = true;
    });
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _saveDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveSubnets() async {
    final prefs = await SharedPreferences.getInstance();
    final values =
        _subnetCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    await prefs.setStringList(_SettingKeys.subnets, values);
  }

  // ---------------------------------------------------------------------------
  // Subnet list helpers
  // ---------------------------------------------------------------------------

  void _addSubnet() {
    setState(() {
      final ctrl = TextEditingController();
      final focus = FocusNode();
      _subnetCtrls.add(ctrl);
      _subnetFocusNodes.add(focus);
    });
    // Focus the new field after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subnetFocusNodes.last.requestFocus();
    });
    _saveSubnets();
  }

  void _removeSubnet(int index) {
    setState(() {
      _subnetCtrls[index].dispose();
      _subnetFocusNodes[index].dispose();
      _subnetCtrls.removeAt(index);
      _subnetFocusNodes.removeAt(index);
    });
    _saveSubnets();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuración')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ================================================================
          // Servidor RDP
          // ================================================================
          _sectionHeader('Servidor RDP'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  TextField(
                    controller: _hostnameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dirección del servidor',
                      hintText: 'serv_ginecologico.huv.gov.co',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                    onChanged: (v) => _saveString(_SettingKeys.hostname, v.trim()),
                  ),
                  TextField(
                    controller: _portCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Puerto',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      final port = int.tryParse(v) ?? 3389;
                      _saveInt(_SettingKeys.port, port);
                    },
                  ),
                  TextField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      hintText: 'Opcional',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    onChanged: (v) => _saveString(_SettingKeys.username, v.trim()),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ================================================================
          // Red Hospitalaria (Split Tunnel)
          // ================================================================
          _sectionHeader('Red Hospitalaria (Split Tunnel)'),

          // Subnets
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
                    child: Text(
                      'Subredes (CIDR)',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ...List.generate(_subnetCtrls.length, (i) {
                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _subnetCtrls[i],
                            focusNode: _subnetFocusNodes[i],
                            decoration: InputDecoration(
                              hintText: '10.0.0.0/8',
                              prefixIcon: const Icon(Icons.hub_outlined, size: 20),
                              suffixIcon: _subnetCtrls.length > 1
                                  ? IconButton(
                                      icon: const Icon(Icons.remove_circle_outline,
                                          color: Colors.red),
                                      tooltip: 'Eliminar subred',
                                      onPressed: () => _removeSubnet(i),
                                    )
                                  : null,
                            ),
                            onChanged: (_) => _saveSubnets(),
                          ),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Agregar subred'),
                      onPressed: _addSubnet,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _gatewayCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Gateway',
                      hintText: '10.0.0.1',
                      prefixIcon: Icon(Icons.router_outlined),
                    ),
                    onChanged: (v) =>
                        _saveString(_SettingKeys.gateway, v.trim()),
                  ),
                  TextField(
                    controller: _interfaceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Interfaz de red',
                      hintText: 'eth0 / en0',
                      prefixIcon: Icon(Icons.cable_outlined),
                    ),
                    onChanged: (v) =>
                        _saveString(_SettingKeys.interface, v.trim()),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ================================================================
          // Diagnóstico
          // ================================================================
          _sectionHeader('Diagnóstico'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  TextField(
                    controller: _pingHostCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Host de prueba',
                      prefixIcon: Icon(Icons.travel_explore_outlined),
                    ),
                    onChanged: (v) =>
                        _saveString(_SettingKeys.pingHost, v.trim()),
                  ),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Tiempo de espera'),
                    subtitle: Text('${_pingTimeout.toInt()} segundos'),
                    trailing: SizedBox(
                      width: 200,
                      child: Slider(
                        value: _pingTimeout,
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: '${_pingTimeout.toInt()} s',
                        onChanged: (v) {
                          setState(() => _pingTimeout = v);
                          _saveDouble(_SettingKeys.pingTimeout, v);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ================================================================
          // Apariencia
          // ================================================================
          _sectionHeader('Apariencia'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('Modo oscuro'),
              trailing: Switch(
                value: _darkMode,
                onChanged: (v) {
                  setState(() => _darkMode = v);
                  _saveBool(_SettingKeys.darkMode, v);
                },
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ================================================================
          // Acerca de
          // ================================================================
          _sectionHeader('Acerca de'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MedLink Connect v1.0.0',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Herramienta de conexión hospitalaria',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
