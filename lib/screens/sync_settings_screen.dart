import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';

/// Connect to / manage a self-hosted Luminotes sync server.
class SyncSettingsScreen extends StatelessWidget {
  const SyncSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud sync')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: sync.isConnected
            ? _ConnectedView(sync: sync)
            : const _ConnectForm(),
      ),
    );
  }
}

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({required this.sync});
  final SyncProvider sync;

  @override
  Widget build(BuildContext context) {
    final last = sync.lastSyncTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusBanner(sync: sync),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dns_outlined),
          title: Text(sync.serverUrl ?? ''),
          subtitle: Text('Signed in as ${sync.username ?? ''}'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: const Text('Last sync'),
          subtitle: Text(last == null ? 'Never' : last.toLocal().toString()),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed:
                  sync.status == SyncStatus.syncing ? null : sync.syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _confirmDisconnect(context, sync),
              icon: const Icon(Icons.logout),
              label: const Text('Disconnect'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmDisconnect(BuildContext context, SyncProvider sync) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect sync?'),
        content: const Text(
          'Your notes stay on this device. They will no longer sync until you '
          'reconnect.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok ?? false) await sync.disconnect();
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.sync});
  final SyncProvider sync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, text, color) = switch (sync.status) {
      SyncStatus.syncing => (Icons.sync, 'Syncing…', scheme.primary),
      SyncStatus.idle => (Icons.cloud_done_outlined, 'Up to date', scheme.primary),
      SyncStatus.error => (Icons.error_outline, sync.lastError ?? 'Sync error', scheme.error),
      SyncStatus.disconnected => (Icons.cloud_off_outlined, 'Not connected', scheme.outline),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (sync.status == SyncStatus.syncing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

class _ConnectForm extends StatefulWidget {
  const _ConnectForm();

  @override
  State<_ConnectForm> createState() => _ConnectFormState();
}

class _ConnectFormState extends State<_ConnectForm> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _url.text.trim();
    final user = _user.text.trim();
    if (url.isEmpty || user.isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Fill in all fields.');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final err = await context.read<SyncProvider>().connect(
          serverUrl: url,
          username: user,
          password: _pass.text,
        );
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text('Connect to your server',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Sync your notes to a self-hosted Luminotes server. Your data stays '
          'on infrastructure you control.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://notes.example.com',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _user,
          decoration: const InputDecoration(
            labelText: 'Username',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: true,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _connecting ? null : _submit,
          icon: _connecting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_sync_outlined),
          label: Text(_connecting ? 'Connecting…' : 'Connect'),
        ),
      ],
    );
  }
}
