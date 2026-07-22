import 'package:flutter/material.dart';
import 'package:medlink_connect/core/rdp_connection_profile.dart';
import 'package:medlink_connect/features/rdp_launcher/default_rdp_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key used to persist the profile list as JSON.
const _profilesKey = 'profiles.savedList';

/// Screen to manage saved RDP connection profiles.
///
/// Profiles are loaded from [SharedPreferences] on init, kept in sync with
/// the [DefaultRdpLauncher] in-memory list, and persisted on every change.
///
/// All user-visible text is in Spanish.
class ProfilesScreen extends StatefulWidget {
  final DefaultRdpLauncher rdpLauncher;

  const ProfilesScreen({super.key, required this.rdpLauncher});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  List<RdpConnectionProfile> _profiles = [];
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw != null && raw.isNotEmpty) {
      final list = RdpConnectionProfile.listFromJson(raw);
      widget.rdpLauncher.loadProfiles(list);
      setState(() => _profiles = list);
    } else {
      setState(() => _profiles = []);
    }
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final json = RdpConnectionProfile.listToJson(_profiles);
    await prefs.setString(_profilesKey, json);
    widget.rdpLauncher.loadProfiles(_profiles);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _selectProfile(int index) {
    setState(() {
      _selectedIndex = (_selectedIndex == index) ? null : index;
    });
  }

  Future<void> _deleteProfile(int index) async {
    final profile = _profiles[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar perfil'),
        content: Text('¿Desea eliminar el perfil "${profile.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      widget.rdpLauncher.removeProfile(profile.name);
      setState(() {
        _profiles.removeAt(index);
        if (_selectedIndex == index) {
          _selectedIndex = null;
        } else if (_selectedIndex != null && _selectedIndex! > index) {
          _selectedIndex = _selectedIndex! - 1;
        }
      });
      await _saveProfiles();
    }
  }

  Future<void> _showAddProfileDialog() async {
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '3389');
    final usernameCtrl = TextEditingController();

    final created = await showDialog<RdpConnectionProfile>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo perfil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Servidor Ginecología',
                ),
              ),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  hintText: '10.0.0.100',
                ),
              ),
              TextField(
                controller: portCtrl,
                decoration: const InputDecoration(labelText: 'Puerto'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  hintText: 'Opcional',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final profile = RdpConnectionProfile(
                name: nameCtrl.text.trim(),
                address: addressCtrl.text.trim(),
                port: int.tryParse(portCtrl.text.trim()) ?? 3389,
                username: usernameCtrl.text.trim().isEmpty
                    ? null
                    : usernameCtrl.text.trim(),
              );
              Navigator.of(ctx).pop(profile);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (created != null) {
      final error = created.validate();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        return;
      }
      widget.rdpLauncher.saveProfile(created);
      setState(() => _profiles = List.of(widget.rdpLauncher.profiles));
      await _saveProfiles();
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfiles de conexión'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddProfileDialog,
        tooltip: 'Nuevo perfil',
        child: const Icon(Icons.add),
      ),
      body: _profiles.isEmpty ? _buildEmptyState(theme) : _buildList(theme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.settings_ethernet_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
            ),
            const SizedBox(height: 16),
            Text(
              'Sin perfiles guardados',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Toque el botón + para agregar un nuevo perfil de conexión RDP.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _profiles.length,
      itemBuilder: (context, index) {
        final profile = _profiles[index];
        final isSelected = _selectedIndex == index;

        return Card(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withAlpha(30),
              child: Icon(
                Icons.desktop_windows_outlined,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.primary,
              ),
            ),
            title: Text(
              profile.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              '${profile.address}:${profile.port}'
              '${profile.username != null && profile.username!.isNotEmpty ? ' — ${profile.username}' : ''}',
            ),
            trailing: isSelected
                ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                : null,
            onTap: () => _selectProfile(index),
            onLongPress: () => _deleteProfile(index),
          ),
        );
      },
    );
  }
}
