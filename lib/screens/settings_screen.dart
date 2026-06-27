/// Settings screen — server host, port (default 4317), and bearer token.
///
/// On save:
/// - Validates required fields (host non-empty, port a valid integer, token non-empty).
/// - Persists config via [ConnectionNotifier.saveConfig], which stores the
///   bearer token in [FlutterSecureStorage] (never shared_preferences — Rule 7).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/connection_provider.dart';

/// Settings screen allowing the user to configure the bastion server address
/// and bearer token.  Port defaults to 4317 per the serve-api spec.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _tokenController;

  bool _saving = false;
  bool _tokenObscured = true;

  @override
  void initState() {
    super.initState();
    final config = ref.read(connectionProvider).config;
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(
      text: config.port == 0 ? '4317' : config.port.toString(),
    );
    _tokenController = TextEditingController();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await ref.read(connectionProvider.notifier).readToken() ?? '';
    if (mounted) {
      _tokenController.text = token;
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  // ---- Validation ---------------------------------------------------------

  String? _validateHost(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Server host is required';
    }
    return null;
  }

  String? _validatePort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Port is required';
    }
    final n = int.tryParse(value.trim());
    if (n == null || n < 1 || n > 65535) {
      return 'Enter a valid port (1–65535)';
    }
    return null;
  }

  String? _validateToken(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Bearer token is required';
    }
    return null;
  }

  // ---- Save ---------------------------------------------------------------

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(connectionProvider.notifier)
          .saveConfig(
            host: _hostController.text.trim(),
            port: int.parse(_portController.text.trim()),
            token: _tokenController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connection Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Host
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Server host',
                  hintText: 'e.g. 100.x.y.z or hostname.tailnet',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                validator: _validateHost,
              ),
              const SizedBox(height: 16),

              // Port
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '4317',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _validatePort,
              ),
              const SizedBox(height: 16),

              // Bearer token (secure)
              TextFormField(
                controller: _tokenController,
                decoration: InputDecoration(
                  labelText: 'Bearer token',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _tokenObscured ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () =>
                        setState(() => _tokenObscured = !_tokenObscured),
                    tooltip: _tokenObscured ? 'Show token' : 'Hide token',
                  ),
                ),
                obscureText: _tokenObscured,
                autocorrect: false,
                enableSuggestions: false,
                validator: _validateToken,
              ),
              const SizedBox(height: 24),

              // Save button
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
