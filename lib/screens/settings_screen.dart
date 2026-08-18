/// Settings screen — server host, port (default 4317), and bearer token.
///
/// On save:
/// - Validates required fields (host non-empty, port a valid integer, token non-empty).
/// - Persists config via [ConnectionNotifier.saveConfig], which stores the
///   bearer token in [FlutterSecureStorage] (never shared_preferences — Rule 7).
///
/// Re-skinned in `BU.10.C` task 5: the two field groups are now [PanelCard]
/// sections, each headed by one [Eyebrow] label. Fields take
/// [AppTokens.surfaceMuted] as their fill, [AppTokens.line] as their
/// hairline border, and [AppTokens.primary] on focus — this is a visual
/// pass only, the [FlutterSecureStorage]-backed token path is untouched
/// (Standing Rule 7).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/engine_api.dart';
import '../state/connection_provider.dart';
import '../theme/status_tones.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/brand/brand.dart';

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
  late final TextEditingController _engineKeyController;

  bool _saving = false;
  bool _tokenObscured = true;
  bool _engineKeyObscured = true;

  /// Result of the most recent engine mount probe, or `null` before the
  /// first probe has resolved. Rendered as a [StatusPill] so the operator
  /// can tell "wrong key" from "server never mounted the engine" from
  /// "not yet configured" — see [EngineStatus]'s five-way doc comment.
  EngineStatus? _engineStatus;

  @override
  void initState() {
    super.initState();
    final config = ref.read(connectionProvider).config;
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(
      text: config.port == 0 ? '4317' : config.port.toString(),
    );
    _tokenController = TextEditingController();
    _engineKeyController = TextEditingController();
    _loadToken();
    _loadEngineKey();
  }

  Future<void> _loadToken() async {
    final token = await ref.read(connectionProvider.notifier).readToken() ?? '';
    if (mounted) {
      _tokenController.text = token;
    }
  }

  Future<void> _loadEngineKey() async {
    final key =
        await ref.read(connectionProvider.notifier).readEngineKey() ?? '';
    if (mounted) {
      _engineKeyController.text = key;
    }
    await _probeEngine();
  }

  /// Probes the engine mount using the CURRENTLY SAVED config/key (not the
  /// unsaved contents of the text fields) and updates [_engineStatus].
  ///
  /// Never throws — [EngineApi.probeMount] captures every failure mode
  /// (missing key, HTTP error, network failure) in its returned status.
  Future<void> _probeEngine() async {
    final config = ref.read(connectionProvider).config;
    final key = await ref.read(connectionProvider.notifier).readEngineKey();
    final engine = EngineApi(host: config.host, port: config.port, key: key);
    try {
      final status = await engine.probeMount();
      if (mounted) {
        setState(() => _engineStatus = status);
      }
    } finally {
      engine.dispose();
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _engineKeyController.dispose();
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
      // Engine key is genuinely optional — an empty field is a valid save
      // meaning "no engine access" (saveEngineKey deletes rather than
      // persisting an empty value; task 1).
      await ref
          .read(connectionProvider.notifier)
          .saveEngineKey(_engineKeyController.text.trim());
      await _probeEngine();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Human-readable label for [_engineStatus], surfaced as a [StatusPill]
  /// so the four/five outcomes stay visually distinguishable rather than
  /// collapsing into a boolean.
  ({String label, StatusPillTone tone}) _engineStatusPresentation(
    EngineStatus? status,
  ) {
    return switch (status) {
      null => (label: 'checking…', tone: StatusPillTone.inProgress),
      EngineStatus.notConfigured => (
        label: 'not configured',
        tone: StatusPillTone.inProgress,
      ),
      EngineStatus.notMounted => (
        label: 'engine not mounted on this server',
        tone: StatusPillTone.needsYou,
      ),
      EngineStatus.unauthorized => (
        label: 'key rejected',
        tone: StatusPillTone.blocked,
      ),
      EngineStatus.available => (
        label: 'connected',
        tone: StatusPillTone.onTrack,
      ),
      EngineStatus.unreachable => (
        label: 'server unreachable',
        tone: StatusPillTone.blocked,
      ),
    };
  }

  /// Shared field decoration: [AppTokens.surfaceMuted] fill, hairline
  /// border in [AppTokens.line], [AppTokens.primary] on focus — the token
  /// treatment named in the block's Task 5 description.
  InputDecoration _fieldDecoration({
    required String labelText,
    String? hintText,
    Widget? suffixIcon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      borderSide: const BorderSide(color: AppTokens.line),
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppTokens.surfaceMuted,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppTokens.primary, width: 2),
      ),
    );
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
              // Connection group: host + port.
              PanelCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Eyebrow(label: 'Connection'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _hostController,
                        style: AppTypography.textTheme.bodyMedium?.copyWith(
                          color: AppTokens.ink,
                        ),
                        decoration: _fieldDecoration(
                          labelText: 'Server host',
                          hintText: 'e.g. 100.x.y.z or hostname.tailnet',
                        ),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        validator: _validateHost,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _portController,
                        style: AppTypography.textTheme.bodyMedium?.copyWith(
                          color: AppTokens.ink,
                        ),
                        decoration: _fieldDecoration(
                          labelText: 'Port',
                          hintText: '4317',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: _validatePort,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Authentication group: bearer token.
              PanelCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Eyebrow(label: 'Authentication'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _tokenController,
                        style: AppTypography.textTheme.bodyMedium?.copyWith(
                          color: AppTokens.ink,
                        ),
                        decoration: _fieldDecoration(
                          labelText: 'Bearer token',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _tokenObscured
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: AppTokens.inkSoft,
                            ),
                            onPressed: () => setState(
                              () => _tokenObscured = !_tokenObscured,
                            ),
                            tooltip: _tokenObscured
                                ? 'Show token'
                                : 'Hide token',
                          ),
                        ),
                        obscureText: _tokenObscured,
                        autocorrect: false,
                        enableSuggestions: false,
                        validator: _validateToken,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Engine group: optional Engine API key (X-API-Key, BU.12.A).
              PanelCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Eyebrow(label: 'Engine'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _engineKeyController,
                        style: AppTypography.textTheme.bodyMedium?.copyWith(
                          color: AppTokens.ink,
                        ),
                        decoration: _fieldDecoration(
                          labelText: 'Engine API key (optional)',
                          hintText: 'Leave blank for no engine access',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _engineKeyObscured
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: AppTokens.inkSoft,
                            ),
                            onPressed: () => setState(
                              () => _engineKeyObscured = !_engineKeyObscured,
                            ),
                            tooltip: _engineKeyObscured
                                ? 'Show key'
                                : 'Hide key',
                          ),
                        ),
                        obscureText: _engineKeyObscured,
                        autocorrect: false,
                        enableSuggestions: false,
                        // No validator: an empty engine key is a valid,
                        // intentional configuration (Standing Rule — see
                        // task 4's acceptance criteria).
                      ),
                      const SizedBox(height: 12),
                      Builder(
                        builder: (context) {
                          final presentation = _engineStatusPresentation(
                            _engineStatus,
                          );
                          // [StatusPill] null-asserts the ambient
                          // [StatusTones] extension; fall back to
                          // [StatusTones.dark] when it is not registered
                          // (e.g. a bare `MaterialApp` in a widget test)
                          // rather than let this crash the screen.
                          final ambientTheme = Theme.of(context);
                          final theme =
                              ambientTheme.extension<StatusTones>() == null
                              ? ambientTheme.copyWith(
                                  extensions: [StatusTones.dark],
                                )
                              : ambientTheme;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Theme(
                              data: theme,
                              child: StatusPill(
                                tone: presentation.tone,
                                label: presentation.label,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
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
