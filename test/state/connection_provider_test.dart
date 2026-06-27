// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/state/connection_provider.dart';

// ---------------------------------------------------------------------------
// Fake FlutterSecureStorage for unit testing
// ---------------------------------------------------------------------------

/// In-memory fake — no platform channels required.
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

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _store.containsKey(key);
  }
}

// ---------------------------------------------------------------------------
// Helper — build a container with the fake storage injected
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer([_FakeSecureStorage? storage]) {
  final fakeStorage = storage ?? _FakeSecureStorage();
  return ProviderContainer(
    overrides: [secureStorageProvider.overrideWithValue(fakeStorage)],
  );
}

void main() {
  // ---- ConnectionConfig ---------------------------------------------------

  group('ConnectionConfig', () {
    test('defaultConfig has host="" and port=4317', () {
      const cfg = ConnectionConfig.defaultConfig;
      expect(cfg.host, '');
      expect(cfg.port, 4317);
    });

    test('copyWith updates only specified fields', () {
      const original = ConnectionConfig(host: 'a', port: 100);
      final updated = original.copyWith(port: 200);
      expect(updated.host, 'a');
      expect(updated.port, 200);
    });

    test('equality is value-based', () {
      const a = ConnectionConfig(host: 'h', port: 4317);
      const b = ConnectionConfig(host: 'h', port: 4317);
      expect(a, equals(b));
    });
  });

  // ---- ConnectionStatus ---------------------------------------------------

  group('ConnectionStatus', () {
    test('all four values exist', () {
      expect(ConnectionStatus.values, hasLength(4));
      expect(
        ConnectionStatus.values,
        containsAll([
          ConnectionStatus.disconnected,
          ConnectionStatus.connecting,
          ConnectionStatus.connected,
          ConnectionStatus.reconnecting,
        ]),
      );
    });
  });

  // ---- ConnectionState ----------------------------------------------------

  group('ConnectionState.initial', () {
    test('initial has defaultConfig and disconnected status', () {
      const s = ConnectionState.initial;
      expect(s.config, ConnectionConfig.defaultConfig);
      expect(s.status, ConnectionStatus.disconnected);
    });
  });

  // ---- ConnectionNotifier -------------------------------------------------

  group('ConnectionNotifier', () {
    test('starts with initial state (default config + disconnected)', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      // Initialize the notifier (triggers _load()) then await its completion.
      container.read(connectionProvider);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(connectionProvider);
      expect(state.config.port, 4317);
      expect(state.status, ConnectionStatus.disconnected);
    });

    test('updateStatus changes status and leaves config unchanged', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      // Initialize then wait for _load()
      container.read(connectionProvider);
      await Future<void>.delayed(Duration.zero);

      container
          .read(connectionProvider.notifier)
          .updateStatus(ConnectionStatus.connecting);
      expect(
        container.read(connectionProvider).status,
        ConnectionStatus.connecting,
      );

      container
          .read(connectionProvider.notifier)
          .updateStatus(ConnectionStatus.connected);
      expect(
        container.read(connectionProvider).status,
        ConnectionStatus.connected,
      );

      // Config unchanged
      expect(container.read(connectionProvider).config.port, 4317);
    });

    test('saveConfig persists host, port, and token', () async {
      final storage = _FakeSecureStorage();
      final container = _makeContainer(storage);
      addTearDown(container.dispose);
      // Initialize then wait for _load()
      container.read(connectionProvider);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(connectionProvider.notifier)
          .saveConfig(host: '100.1.2.3', port: 4317, token: 'secret-token');

      final state = container.read(connectionProvider);
      expect(state.config.host, '100.1.2.3');
      expect(state.config.port, 4317);

      // Token is stored in secure storage
      final storedToken = await container
          .read(connectionProvider.notifier)
          .readToken();
      expect(storedToken, 'secret-token');
    });

    test('readToken returns null when token has not been set', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      // Initialize provider (no need to await _load for this test)
      container.read(connectionProvider);

      final token = await container
          .read(connectionProvider.notifier)
          .readToken();
      expect(token, isNull);
    });

    test('_load restores persisted host and port on startup', () async {
      final storage = _FakeSecureStorage();

      // Pre-seed storage as if a previous session saved these values
      await storage.write(key: 'bastion.server.host', value: 'my-host');
      await storage.write(key: 'bastion.server.port', value: '9000');

      final container = _makeContainer(storage);
      addTearDown(container.dispose);

      // Initialize then wait for _load() to restore persisted values
      container.read(connectionProvider);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(connectionProvider);
      expect(state.config.host, 'my-host');
      expect(state.config.port, 9000);
    });

    test('_load falls back to port 4317 when stored port is invalid', () async {
      final storage = _FakeSecureStorage();
      await storage.write(key: 'bastion.server.host', value: 'h');
      await storage.write(key: 'bastion.server.port', value: 'not-a-number');

      final container = _makeContainer(storage);
      addTearDown(container.dispose);
      container.read(connectionProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(connectionProvider).config.port, 4317);
    });

    test('status can cycle through all four values', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      // Initialize then wait for _load()
      container.read(connectionProvider);
      await Future<void>.delayed(Duration.zero);

      final notifier = container.read(connectionProvider.notifier);
      for (final status in ConnectionStatus.values) {
        notifier.updateStatus(status);
        expect(container.read(connectionProvider).status, status);
      }
    });
  });
}
