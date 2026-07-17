// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/state/commands_provider.dart';
import 'package:bastion_ui/state/connection_provider.dart'
    show secureStorageProvider;

// ---------------------------------------------------------------------------
// In-memory fake FlutterSecureStorage — no platform channels required.
// ---------------------------------------------------------------------------

class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String?> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _store[key];
  }
}

ProviderContainer _makeContainer([_FakeSecureStorage? storage]) {
  final fakeStorage = storage ?? _FakeSecureStorage();
  return ProviderContainer(
    overrides: [secureStorageProvider.overrideWithValue(fakeStorage)],
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('PaletteCommand', () {
    test('round-trips through toJson/fromJson', () {
      const cmd = PaletteCommand(label: 'Prime', command: '/prime');
      final json = cmd.toJson();
      final restored = PaletteCommand.fromJson(json);
      expect(restored, equals(cmd));
    });

    test('equality is value-based', () {
      const a = PaletteCommand(label: 'a', command: '/a');
      const b = PaletteCommand(label: 'a', command: '/a');
      expect(a, equals(b));
    });
  });

  group('CommandsNotifier', () {
    test('seeds default commands on first run (no stored value)', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      container.read(commandsProvider);
      await _settle();

      expect(container.read(commandsProvider), equals(defaultPaletteCommands));
      expect(container.read(commandsProvider), isNotEmpty);
    });

    test('add appends and persists', () async {
      final storage = _FakeSecureStorage();
      final container = _makeContainer(storage);
      addTearDown(container.dispose);

      container.read(commandsProvider);
      await _settle();

      const newCmd = PaletteCommand(label: 'Status', command: '/status');
      await container.read(commandsProvider.notifier).add(newCmd);

      expect(container.read(commandsProvider), contains(newCmd));

      // A fresh notifier over the same storage sees the persisted addition.
      final container2 = _makeContainer(storage);
      addTearDown(container2.dispose);
      container2.read(commandsProvider);
      await _settle();
      expect(container2.read(commandsProvider), contains(newCmd));
    });

    test('update edits in place and persists', () async {
      final storage = _FakeSecureStorage();
      final container = _makeContainer(storage);
      addTearDown(container.dispose);

      container.read(commandsProvider);
      await _settle();

      const edited = PaletteCommand(label: 'Renamed', command: '/renamed');
      await container.read(commandsProvider.notifier).update(0, edited);

      expect(container.read(commandsProvider)[0], equals(edited));

      final container2 = _makeContainer(storage);
      addTearDown(container2.dispose);
      container2.read(commandsProvider);
      await _settle();
      expect(container2.read(commandsProvider)[0], equals(edited));
    });

    test('delete removes and persists', () async {
      final storage = _FakeSecureStorage();
      final container = _makeContainer(storage);
      addTearDown(container.dispose);

      container.read(commandsProvider);
      await _settle();

      final originalLength = container.read(commandsProvider).length;
      final removed = container.read(commandsProvider)[0];
      await container.read(commandsProvider.notifier).delete(0);

      expect(container.read(commandsProvider).length, originalLength - 1);
      expect(container.read(commandsProvider), isNot(contains(removed)));

      final container2 = _makeContainer(storage);
      addTearDown(container2.dispose);
      container2.read(commandsProvider);
      await _settle();
      expect(container2.read(commandsProvider).length, originalLength - 1);
    });

    test('reorder moves an entry and persists', () async {
      final storage = _FakeSecureStorage();
      final container = _makeContainer(storage);
      addTearDown(container.dispose);

      container.read(commandsProvider);
      await _settle();

      final first = container.read(commandsProvider)[0];
      await container.read(commandsProvider.notifier).reorder(0, 1);

      expect(container.read(commandsProvider)[1], equals(first));

      final container2 = _makeContainer(storage);
      addTearDown(container2.dispose);
      container2.read(commandsProvider);
      await _settle();
      expect(container2.read(commandsProvider)[1], equals(first));
    });

    test(
      'a fresh notifier over the same storage reproduces the edited list (restart survival)',
      () async {
        final storage = _FakeSecureStorage();
        final container = _makeContainer(storage);
        addTearDown(container.dispose);

        container.read(commandsProvider);
        await _settle();

        final notifier = container.read(commandsProvider.notifier);
        await notifier.add(
          const PaletteCommand(label: 'Custom', command: '/custom'),
        );
        await notifier.delete(0);

        final expected = container.read(commandsProvider);

        final container2 = _makeContainer(storage);
        addTearDown(container2.dispose);
        container2.read(commandsProvider);
        await _settle();

        expect(container2.read(commandsProvider), equals(expected));
      },
    );

    test('corrupt stored JSON falls back to defaults', () async {
      final storage = _FakeSecureStorage();
      await storage.write(key: 'bastion.commands.list', value: 'not-json{{{');

      final container = _makeContainer(storage);
      addTearDown(container.dispose);
      container.read(commandsProvider);
      await _settle();

      expect(container.read(commandsProvider), equals(defaultPaletteCommands));
    });

    test('stored non-list JSON falls back to defaults', () async {
      final storage = _FakeSecureStorage();
      await storage.write(key: 'bastion.commands.list', value: '{"a": 1}');

      final container = _makeContainer(storage);
      addTearDown(container.dispose);
      container.read(commandsProvider);
      await _settle();

      expect(container.read(commandsProvider), equals(defaultPaletteCommands));
    });

    test('empty stored string falls back to defaults', () async {
      final storage = _FakeSecureStorage();
      await storage.write(key: 'bastion.commands.list', value: '');

      final container = _makeContainer(storage);
      addTearDown(container.dispose);
      container.read(commandsProvider);
      await _settle();

      expect(container.read(commandsProvider), equals(defaultPaletteCommands));
    });

    test(
      'update/delete/reorder with an out-of-range index is a no-op',
      () async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        container.read(commandsProvider);
        await _settle();

        final before = container.read(commandsProvider);
        final notifier = container.read(commandsProvider.notifier);

        await notifier.update(
          99,
          const PaletteCommand(label: 'x', command: '/x'),
        );
        await notifier.delete(-1);
        await notifier.reorder(0, 99);

        expect(container.read(commandsProvider), equals(before));
      },
    );
  });
}
