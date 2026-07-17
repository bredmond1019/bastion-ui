/// Riverpod state for the user-editable command-palette entries.
///
/// This is app-side, user-editable config — NOT part of the serve-api
/// contract — so [PaletteCommand] is a local model (not mirrored from
/// `serve-api.md`).
///
/// [CommandsNotifier] persists the palette through the EXISTING
/// [secureStorageProvider] seam (JSON-encoded list under [_kCommandsKey]) —
/// per the spec's Persistence decision, no new dependency (e.g.
/// `shared_preferences`) is added.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'connection_provider.dart' show secureStorageProvider;

// ---------------------------------------------------------------------------
// Storage key
// ---------------------------------------------------------------------------

const _kCommandsKey = 'bastion.commands.list';

// ---------------------------------------------------------------------------
// Value object
// ---------------------------------------------------------------------------

/// A single user-editable palette entry: a display label paired with the
/// slash-command string that gets fired at Bastion.
final class PaletteCommand {
  final String label;
  final String command;

  const PaletteCommand({required this.label, required this.command});

  factory PaletteCommand.fromJson(Map<String, dynamic> json) {
    return PaletteCommand(
      label: json['label'] as String? ?? '',
      command: json['command'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'command': command};

  PaletteCommand copyWith({String? label, String? command}) => PaletteCommand(
    label: label ?? this.label,
    command: command ?? this.command,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaletteCommand &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          command == other.command;

  @override
  int get hashCode => Object.hash(label, command);

  @override
  String toString() => 'PaletteCommand(label: $label, command: $command)';
}

// ---------------------------------------------------------------------------
// Defaults
// ---------------------------------------------------------------------------

/// Sensible non-empty default set seeded on first run (no stored value yet).
const List<PaletteCommand> defaultPaletteCommands = [
  PaletteCommand(label: 'Prime', command: '/prime'),
  PaletteCommand(label: 'SDLC Flow', command: '/sdlc-flow'),
  PaletteCommand(label: 'Code Review', command: '/code-review'),
  PaletteCommand(label: 'Handoff', command: '/handoff'),
];

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages the persisted, user-editable command-palette list.
///
/// Persistence contract:
/// - The list is JSON-encoded and stored under [_kCommandsKey] in
///   [FlutterSecureStorage] (reusing the existing secure-storage seam — see
///   the block spec's Persistence decision; this is not Rule 7 token data,
///   just the repo's only local store).
/// - A missing or unparseable stored value falls back to
///   [defaultPaletteCommands] rather than throwing.
class CommandsNotifier extends StateNotifier<List<PaletteCommand>> {
  CommandsNotifier(this._storage) : super(const []) {
    _load();
  }

  final FlutterSecureStorage _storage;

  // ---- Persistence --------------------------------------------------------

  /// Load persisted commands from secure storage on startup.
  ///
  /// Falls back to [defaultPaletteCommands] when nothing is stored yet, or
  /// when the stored value is corrupt/unparseable.
  Future<void> _load() async {
    final raw = await _storage.read(key: _kCommandsKey);
    final commands = _decode(raw);
    // Guard against disposal during the async gap.
    if (!mounted) return;
    state = commands;
  }

  /// Decode a stored JSON string into a command list, falling back to
  /// defaults on `null`, an empty string, or any parse failure.
  List<PaletteCommand> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaultPaletteCommands;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return defaultPaletteCommands;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PaletteCommand.fromJson)
          .toList();
    } catch (_) {
      return defaultPaletteCommands;
    }
  }

  /// Persist the current [state] to secure storage.
  Future<void> _persist() async {
    final encoded = jsonEncode(state.map((c) => c.toJson()).toList());
    await _storage.write(key: _kCommandsKey, value: encoded);
  }

  // ---- Mutations ------------------------------------------------------

  /// Append a new command entry, then persist.
  Future<void> add(PaletteCommand command) async {
    state = [...state, command];
    await _persist();
  }

  /// Replace the entry at [index] with [command], then persist.
  Future<void> update(int index, PaletteCommand command) async {
    if (index < 0 || index >= state.length) return;
    final next = [...state];
    next[index] = command;
    state = next;
    await _persist();
  }

  /// Remove the entry at [index], then persist.
  Future<void> delete(int index) async {
    if (index < 0 || index >= state.length) return;
    final next = [...state]..removeAt(index);
    state = next;
    await _persist();
  }

  /// Move the entry at [oldIndex] to [newIndex], then persist.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= state.length ||
        newIndex < 0 ||
        newIndex >= state.length) {
      return;
    }
    final next = [...state];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    state = next;
    await _persist();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Top-level command-palette provider — exposes the persisted, user-editable
/// [PaletteCommand] list and the [CommandsNotifier] for mutations.
final commandsProvider =
    StateNotifierProvider<CommandsNotifier, List<PaletteCommand>>((ref) {
      return CommandsNotifier(ref.watch(secureStorageProvider));
    });
