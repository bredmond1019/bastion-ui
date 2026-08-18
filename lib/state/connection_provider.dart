/// Riverpod providers for server connection config and connection state.
///
/// - [ConnectionConfig] holds the server host and port (default port: 4317).
/// - [ConnectionStatus] is the live socket state enum.
/// - [ConnectionState] bundles config + status.
/// - [ConnectionNotifier] persists config + token via [FlutterSecureStorage]
///   and exposes status transitions.
///
/// Rule 7: bearer token is ALWAYS stored in [FlutterSecureStorage], never in
/// shared_preferences or any other unencrypted store.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ---------------------------------------------------------------------------
// Storage key constants
// ---------------------------------------------------------------------------

const _kHost = 'bastion.server.host';
const _kPort = 'bastion.server.port';
const _kToken = 'bastion.auth.token';
const _kEngineKey = 'bastion.auth.engine_key';

// ---------------------------------------------------------------------------
// Value objects
// ---------------------------------------------------------------------------

/// Immutable server connection configuration.
final class ConnectionConfig {
  final String host;
  final int port;

  const ConnectionConfig({required this.host, required this.port});

  /// Convenience default — host is empty (unconfigured), port 4317 per the spec.
  static const ConnectionConfig defaultConfig = ConnectionConfig(
    host: '',
    port: 4317,
  );

  ConnectionConfig copyWith({String? host, int? port}) =>
      ConnectionConfig(host: host ?? this.host, port: port ?? this.port);

  @override
  bool operator ==(Object other) =>
      other is ConnectionConfig && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => 'ConnectionConfig(host: $host, port: $port)';
}

// ---------------------------------------------------------------------------
// Connection status
// ---------------------------------------------------------------------------

/// Live WebSocket / server connection status.
enum ConnectionStatus { disconnected, connecting, connected, reconnecting }

// ---------------------------------------------------------------------------
// State bundle
// ---------------------------------------------------------------------------

/// Combined state for the connection provider (config + live status).
final class ConnectionState {
  final ConnectionConfig config;
  final ConnectionStatus status;

  const ConnectionState({required this.config, required this.status});

  /// Default initial state — default config, disconnected.
  static const ConnectionState initial = ConnectionState(
    config: ConnectionConfig.defaultConfig,
    status: ConnectionStatus.disconnected,
  );

  ConnectionState copyWith({
    ConnectionConfig? config,
    ConnectionStatus? status,
  }) => ConnectionState(
    config: config ?? this.config,
    status: status ?? this.status,
  );

  @override
  bool operator ==(Object other) =>
      other is ConnectionState &&
      other.config == config &&
      other.status == status;

  @override
  int get hashCode => Object.hash(config, status);

  @override
  String toString() => 'ConnectionState(config: $config, status: $status)';
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages persistent server config, secure token storage, and connection status.
///
/// Persistence contract:
/// - [host] and [port] are stored under their own secure-storage keys.
/// - The bearer token is stored under [_kToken] in [FlutterSecureStorage]
///   (Rule 7 — never shared_preferences).
class ConnectionNotifier extends StateNotifier<ConnectionState> {
  ConnectionNotifier(this._storage) : super(ConnectionState.initial) {
    _load();
  }

  final FlutterSecureStorage _storage;

  // ---- Persistence --------------------------------------------------------

  /// Load persisted host/port from secure storage on startup.
  Future<void> _load() async {
    final host = await _storage.read(key: _kHost) ?? '';
    final portStr = await _storage.read(key: _kPort);
    final port = int.tryParse(portStr ?? '') ?? 4317;
    // Guard against disposal during the async gap.
    if (!mounted) return;
    state = state.copyWith(
      config: ConnectionConfig(host: host, port: port),
    );
  }

  /// Persist server config and bearer token, then update in-memory state.
  ///
  /// [token] is always written to [FlutterSecureStorage] (Rule 7).
  Future<void> saveConfig({
    required String host,
    required int port,
    required String token,
  }) async {
    await Future.wait([
      _storage.write(key: _kHost, value: host),
      _storage.write(key: _kPort, value: port.toString()),
      _storage.write(key: _kToken, value: token),
    ]);
    state = state.copyWith(
      config: ConnectionConfig(host: host, port: port),
    );
  }

  /// Read the stored bearer token (returns `null` if not yet configured).
  Future<String?> readToken() => _storage.read(key: _kToken);

  /// Read the stored engine API key (returns `null` if not yet configured).
  ///
  /// Mirrors [readToken]. The engine key is a separate credential (§18.2.1)
  /// stored under [_kEngineKey], never surfaced via [ConnectionConfig] or
  /// [ConnectionState] (Rule 7 — neither value object may be able to emit a
  /// secret through its `toString()`).
  Future<String?> readEngineKey() => _storage.read(key: _kEngineKey);

  /// Persist (or clear) the engine API key.
  ///
  /// A `null` or empty [key] DELETES the storage entry rather than writing
  /// an empty value — serve-api §18.2.1 rejects an empty `X-API-Key` header
  /// with 401, so on this side "empty" must mean "not configured", not
  /// "configured with an empty secret".
  Future<void> saveEngineKey(String? key) async {
    if (key == null || key.isEmpty) {
      await _storage.delete(key: _kEngineKey);
    } else {
      await _storage.write(key: _kEngineKey, value: key);
    }
  }

  // ---- Status transitions -------------------------------------------------

  /// Update the live connection status (called by the socket service).
  ///
  /// Not debounced: this provider does not itself own or consume a raw WS
  /// stream — `main.dart` bridges `BastionSocket.statusStream` into a single
  /// call per discrete status transition (disconnected/connecting/connected/
  /// reconnecting), so there is no high-frequency flood to coalesce here. If
  /// a future socket implementation starts flapping this status rapidly,
  /// debounce at the bridging call site (or wrap `statusStream` itself with
  /// `.debounceTime`), not inside this notifier.
  void updateStatus(ConnectionStatus status) {
    state = state.copyWith(status: status);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides the [FlutterSecureStorage] instance (overridable in tests).
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

/// Top-level connection provider — exposes [ConnectionState] and the
/// [ConnectionNotifier] for status transitions and config persistence.
final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionState>((ref) {
      return ConnectionNotifier(ref.watch(secureStorageProvider));
    });
