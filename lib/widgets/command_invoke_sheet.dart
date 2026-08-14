/// Modal bottom sheet shown when a command-palette entry is fired.
///
/// Lets the user choose between **inject** (fire the command at an existing
/// session) and **spawn** (launch a new session first), collects the mode's
/// required fields, then calls `POST /api/actions/command`
/// ([BastionApi.postCommand], serve-api.md §12) and resolves with the
/// **server-returned** target session id — never a client-guessed one.
///
/// - Disables the invoke control until the active mode's required fields
///   are satisfied (mirrors the server's §12.3 `C006` validation client-side
///   so the obvious mistakes never round-trip).
/// - Shows a pending state for the duration of the call — spawn waits on
///   server-side readiness and can legitimately take tens of seconds.
/// - On success, pops the sheet with the session id (`Navigator.pop`); on
///   [ApiError] / [FatalAuthError] it surfaces the server's message inline
///   and does NOT pop with a session id (the caller sees `null` only on an
///   explicit cancel — a failed invoke keeps the sheet open so the user can
///   retry or dismiss it themselves).
///
/// Re-skinned in `BU.10.C` task 5: the sheet body sits on an
/// [AppTokens.surface] ground with rounded top corners, headed by one
/// [Eyebrow] label; the fired command string renders in the mono family
/// (content, not a label — no uppercase/tracking applied to it) and the
/// inline error message reads through [AppTokens.destructive].
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/action_dto.dart';
import '../models/dto.dart' show ErrorPayload;
import '../services/bastion_api.dart';
import '../state/sessions_provider.dart'
    show bastionApiProvider, sessionsProvider;
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'brand/brand.dart';

/// Presents [CommandInvokeSheet] as a modal bottom sheet for [command].
///
/// Resolves with the target session id on a successful invocation, or
/// `null` if the sheet is dismissed/cancelled without one.
Future<String?> showCommandInvokeSheet(
  BuildContext context, {
  required String command,
}) {
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => CommandInvokeSheet(command: command),
  );
}

/// The inject/spawn chooser sheet body for [command].
///
/// Exposed as a standalone widget (rather than only the [showCommandInvokeSheet]
/// helper) so it is directly widget-testable.
class CommandInvokeSheet extends ConsumerStatefulWidget {
  const CommandInvokeSheet({super.key, required this.command});

  /// The slash-command string to fire (from the fired palette entry).
  final String command;

  @override
  ConsumerState<CommandInvokeSheet> createState() => _CommandInvokeSheetState();
}

class _CommandInvokeSheetState extends ConsumerState<CommandInvokeSheet> {
  CommandMode _mode = CommandMode.inject;
  String? _selectedSession;
  CommandModel? _model;
  bool _pending = false;
  String? _errorMessage;

  final _nameController = TextEditingController();
  final _dirController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Text fields drive `_canInvoke`, which isn't recomputed on plain text
    // changes unless we explicitly rebuild.
    _nameController.addListener(_onFieldChanged);
    _dirController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFieldChanged);
    _dirController.removeListener(_onFieldChanged);
    _nameController.dispose();
    _dirController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  /// Whether the active mode's required fields are satisfied.
  bool get _canInvoke {
    if (_pending) return false;
    switch (_mode) {
      case CommandMode.inject:
        return _selectedSession != null && _selectedSession!.isNotEmpty;
      case CommandMode.spawn:
        return _nameController.text.trim().isNotEmpty;
    }
  }

  Future<void> _invoke() async {
    final api = ref.read(bastionApiProvider);
    if (api == null) return;

    setState(() {
      _pending = true;
      _errorMessage = null;
    });

    final dir = _dirController.text.trim();
    final request = CommandRequest(
      mode: _mode,
      session: _mode == CommandMode.inject ? _selectedSession : null,
      name: _mode == CommandMode.spawn ? _nameController.text.trim() : null,
      dir: _mode == CommandMode.spawn && dir.isNotEmpty ? dir : null,
      model: _mode == CommandMode.spawn ? _model : null,
      command: widget.command,
    );

    try {
      final sessionId = await api.postCommand(request);
      if (!mounted) return;
      Navigator.of(context).pop(sessionId);
    } on FatalAuthError catch (e) {
      if (!mounted) return;
      setState(() {
        _pending = false;
        _errorMessage = e.payload.message ?? 'Authentication failed.';
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _pending = false;
        _errorMessage = _describeApiError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pending = false;
        _errorMessage = 'Failed to run command: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);
    return Container(
      decoration: const BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXxl),
        ),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Eyebrow(label: 'Invoke'),
            const SizedBox(height: 10),
            Text(
              widget.command,
              style: AppTypography.mono.copyWith(color: AppTokens.ink),
            ),
            const SizedBox(height: 12),
            SegmentedButton<CommandMode>(
              key: const Key('command-invoke-mode-toggle'),
              segments: const [
                ButtonSegment(value: CommandMode.inject, label: Text('Inject')),
                ButtonSegment(value: CommandMode.spawn, label: Text('Spawn')),
              ],
              selected: {_mode},
              onSelectionChanged: _pending
                  ? null
                  : (selection) => setState(() {
                      _mode = selection.first;
                      _errorMessage = null;
                    }),
            ),
            const SizedBox(height: 12),
            if (_mode == CommandMode.inject)
              _buildInjectFields(sessions)
            else
              _buildSpawnFields(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                key: const Key('command-invoke-error'),
                style: AppTypography.textTheme.bodyMedium?.copyWith(
                  color: AppTokens.destructive,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('command-invoke-button'),
              onPressed: _canInvoke ? _invoke : null,
              child: _pending
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Run'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInjectFields(List<dynamic> sessions) {
    final names = sessions.map((s) => s.name as String).toList(growable: false);
    // Selected session may no longer be live; drop it rather than crash the
    // dropdown on a stale value.
    if (_selectedSession != null && !names.contains(_selectedSession)) {
      _selectedSession = null;
    }
    return DropdownButtonFormField<String>(
      key: const Key('command-invoke-session'),
      initialValue: _selectedSession,
      decoration: const InputDecoration(labelText: 'Session'),
      items: [
        for (final name in names)
          DropdownMenuItem(value: name, child: Text(name)),
      ],
      onChanged: _pending
          ? null
          : (value) => setState(() => _selectedSession = value),
    );
  }

  Widget _buildSpawnFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('command-invoke-name'),
          controller: _nameController,
          enabled: !_pending,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('command-invoke-dir'),
          controller: _dirController,
          enabled: !_pending,
          decoration: const InputDecoration(labelText: 'Directory (optional)'),
        ),
        const SizedBox(height: 8),
        SegmentedButton<CommandModel?>(
          key: const Key('command-invoke-model'),
          segments: const [
            ButtonSegment(value: null, label: Text('Default')),
            ButtonSegment(value: CommandModel.sonnet, label: Text('Sonnet')),
            ButtonSegment(value: CommandModel.opus, label: Text('Opus')),
          ],
          selected: {_model},
          onSelectionChanged: _pending
              ? null
              : (selection) => setState(() => _model = selection.first),
        ),
      ],
    );
  }
}

/// Best-effort human-readable message for an [ApiError] — tries the §10.4
/// `ErrorPayload` shape (`message`, else `error`, else `code`) and falls
/// back to a generic status-coded message when the body doesn't parse as
/// the expected JSON shape.
String _describeApiError(ApiError error) {
  try {
    final json = jsonDecode(error.body) as Map<String, dynamic>;
    final payload = ErrorPayload.fromJson(json);
    final message = payload.message ?? payload.error;
    if (message != null && message.isNotEmpty) return message;
    return 'Command failed (${payload.code}).';
  } catch (_) {
    return 'Command failed (${error.statusCode}).';
  }
}
