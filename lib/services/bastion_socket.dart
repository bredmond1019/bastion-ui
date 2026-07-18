/// WebSocket socket service for `bastion serve /ws`.
///
/// Connects to `ws://<host>:<port>/ws` using an [IOWebSocketChannel] so the
/// bearer `Authorization` header can be set on the upgrade handshake.  Exposes
/// a typed [BastionFrame] stream decoded via `models/frame.dart`, a live
/// [ConnectionStatus] stream, and capped exponential-backoff reconnect.
///
/// Auth failures (401 / "unauthorized" on the handshake or in-stream) are
/// treated as **fatal**: reconnect stops and [isFatalAuth] is set to `true`.
///
/// Rule 7 (CLAUDE.md): the token is read by the caller — this service only
/// consumes it; it never persists the token itself.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';

import '../models/frame.dart';
import '../state/connection_provider.dart';

// ---------------------------------------------------------------------------
// Transport abstraction (enables unit-testing without a real network)
// ---------------------------------------------------------------------------

/// Thin interface over a single WebSocket connection attempt.
///
/// The production implementation wraps [IOWebSocketChannel]; tests inject a
/// [FakeWsTransport] (or any other fake) via [TransportFactory].
abstract interface class WsTransport {
  /// Completes when the WebSocket handshake succeeds, or throws on failure
  /// (e.g. the server returned a 401).
  Future<void> get ready;

  /// Inbound messages from the server (text frames).
  Stream<dynamic> get messageStream;

  /// Send a text frame to the server.
  void send(String data);

  /// Close this connection.
  Future<void> close();
}

// ---------------------------------------------------------------------------
// Production transport
// ---------------------------------------------------------------------------

/// [IOWebSocketChannel]-backed transport that sets the bearer header on the
/// HTTP upgrade.
class _IoWsTransport implements WsTransport {
  _IoWsTransport(Uri uri, {Map<String, dynamic>? headers})
    : _channel = IOWebSocketChannel.connect(uri, headers: headers ?? {});

  final IOWebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get messageStream => _channel.stream;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.sink.close();
}

// ---------------------------------------------------------------------------
// Factory typedef + default
// ---------------------------------------------------------------------------

/// Creates a [WsTransport] for the given URI and optional headers.
///
/// The default uses [IOWebSocketChannel] (required for header injection).
/// Inject a fake factory in unit tests.
typedef TransportFactory =
    WsTransport Function(Uri uri, {Map<String, dynamic>? headers});

WsTransport _defaultTransportFactory(
  Uri uri, {
  Map<String, dynamic>? headers,
}) => _IoWsTransport(uri, headers: headers);

// ---------------------------------------------------------------------------
// BastionSocket
// ---------------------------------------------------------------------------

/// Manages the `ws://<host>:<port>/ws` connection lifecycle.
///
/// **Usage:**
/// ```dart
/// final socket = BastionSocket(host: 'myhost', port: 4317, token: 'tok');
/// socket.statusStream.listen((s) { /* update UI */ });
/// socket.frames.listen((frame) { /* handle frame */ });
/// socket.connect();
/// // ...
/// await socket.dispose();
/// ```
///
/// After [dispose] the instance cannot be reused — create a new one.
class BastionSocket {
  // Named parameters host/port/token map to private fields; `this._host` as
  // an initializing formal would rename the public parameter to `_host:` (a
  // library-private identifier), which breaks callers outside this library.
  // ignore: prefer_initializing_formals
  BastionSocket({
    required String host,
    required int port,
    required String token,
    TransportFactory? transportFactory,
    Duration Function(int attempt)? backoffSchedule,
    Duration? disposeCloseTimeout,
  }) : _host = host, // ignore: prefer_initializing_formals
       _port = port, // ignore: prefer_initializing_formals
       _token = token, // ignore: prefer_initializing_formals
       _transportFactory = transportFactory ?? _defaultTransportFactory,
       _backoffSchedule = backoffSchedule ?? computeBackoff,
       _disposeCloseTimeout =
           disposeCloseTimeout ?? _defaultDisposeCloseTimeout;

  final String _host;
  final int _port;
  final String _token;
  final TransportFactory _transportFactory;
  final Duration Function(int attempt) _backoffSchedule;

  /// Upper bound on how long [dispose] waits for the transport to close.
  ///
  /// A transport whose WebSocket upgrade never completed (e.g. a fatal-auth
  /// `401` during connect) can leave `IOWebSocketChannel.sink.close()` pending
  /// forever; without a bound, [dispose] would hang the caller. Injectable so
  /// unit tests can assert the bound without a real multi-second wait.
  final Duration _disposeCloseTimeout;

  /// Default [dispose] transport-close bound used in production.
  static const Duration _defaultDisposeCloseTimeout = Duration(seconds: 5);

  // ---- Status stream ------------------------------------------------------

  // sync: true so status changes are delivered synchronously to listeners —
  // important for the UI to reflect state immediately and for tests to verify
  // transitions without an extra event-loop round.
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast(sync: true);

  /// Stream of [ConnectionStatus] transitions (each state change emits once).
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  ConnectionStatus _status = ConnectionStatus.disconnected;

  /// Most recently emitted [ConnectionStatus].
  ConnectionStatus get status => _status;

  // ---- Frame stream -------------------------------------------------------

  final StreamController<BastionFrame> _frameController =
      StreamController<BastionFrame>.broadcast();

  /// Typed stream of decoded [BastionFrame]s received from the server.
  Stream<BastionFrame> get frames => _frameController.stream;

  // ---- Fatal auth flag ----------------------------------------------------

  bool _fatalAuth = false;

  /// `true` after the server rejects the bearer token.
  ///
  /// When `true`, no further reconnect attempts are made.  Construct a new
  /// [BastionSocket] with a corrected token to retry.
  bool get isFatalAuth => _fatalAuth;

  // ---- Internals ----------------------------------------------------------

  WsTransport? _transport;
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;
  int _attempt = 0;
  Timer? _reconnectTimer;

  // ---- Active-subscription registry ---------------------------------------
  //
  // Tracks topics currently subscribed (via the existing send() path) so a
  // transient drop can replay them on the *next* successful reconnect — the
  // notifiers' constructors only ever subscribe once, so without this replay
  // their live streams would go silent after a reconnect. A [LinkedHashSet]
  // (the default for a `{}` Set literal) preserves insertion order, giving a
  // deterministic replay order.
  final Set<String> _activeTopics = {};

  /// `true` once the socket has completed at least one successful connect.
  /// Replay only happens on the *next* connect after this becomes `true` —
  /// never on the very first connect (the notifiers already subscribe then).
  bool _everConnected = false;

  // ---- Public API ---------------------------------------------------------

  /// Begin (or resume) the connection lifecycle.
  ///
  /// No-op if already connecting/connected, disposed, or after a fatal auth
  /// failure.
  void connect() {
    if (_disposed || _fatalAuth) return;
    if (_status == ConnectionStatus.connecting ||
        _status == ConnectionStatus.connected) {
      return;
    }
    _setStatus(ConnectionStatus.connecting);
    _doConnect();
  }

  /// Send a JSON-encodable map over the socket.
  ///
  /// No-op if not currently [ConnectionStatus.connected].
  void send(Map<String, dynamic> json) {
    _trackSubscription(json);
    if (_status == ConnectionStatus.connected) {
      _transport?.send(jsonEncode(json));
    }
  }

  /// Permanently close the socket.
  ///
  /// After [dispose] the instance cannot be reused.
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    // A transport whose handshake never completed (e.g. a fatal-auth 401
    // during connect) can leave close() pending forever. Bound it so dispose()
    // always completes promptly — hanging here would wedge navigation,
    // reconnect-with-a-new-token, and app teardown.
    final transport = _transport;
    _transport = null;
    if (transport != null) {
      await transport.close().timeout(_disposeCloseTimeout, onTimeout: () {});
    }
    if (!_statusController.isClosed) await _statusController.close();
    if (!_frameController.isClosed) await _frameController.close();
  }

  // ---- Default backoff (public for direct testing) ------------------------

  /// Default capped exponential backoff schedule.
  ///
  /// Returns: 1 s, 2 s, 4 s, 8 s, 16 s, 32 s (cap for attempt ≥ 5).
  static Duration computeBackoff(int attempt) {
    final secs = 1 << attempt.clamp(0, 5); // 2^0 … 2^5 = 1…32
    return Duration(seconds: secs);
  }

  // ---- Internal -----------------------------------------------------------

  void _setStatus(ConnectionStatus s) {
    _status = s;
    if (!_statusController.isClosed) {
      _statusController.add(s);
    }
  }

  Future<void> _doConnect() async {
    // Cancel any lingering subscription from the previous attempt.
    // Do NOT await here — we want the transport factory call below to happen
    // synchronously (before the first real suspension point) so that tests
    // can inspect the created transport immediately after connect().
    // By the time _doConnect is called again the stream is already done, so
    // cancel() on a closed subscription is effectively a no-op.
    final oldSub = _sub;
    _sub = null;
    oldSub?.cancel(); // fire-and-forget (ignore: discarded_futures)

    final uri = Uri.parse('ws://$_host:$_port/ws');
    final headers = <String, dynamic>{'Authorization': 'Bearer $_token'};

    WsTransport transport;
    try {
      transport = _transportFactory(uri, headers: headers);
    } catch (_) {
      // Synchronous factory failure — treat as a transient error.
      _scheduleReconnect();
      return;
    }
    _transport = transport;

    // Await the WebSocket handshake; a 401 here is fatal.
    try {
      await transport.ready;
    } catch (e) {
      if (_disposed) return;
      if (_isAuthError(e)) {
        _fatalAuth = true;
        _setStatus(ConnectionStatus.disconnected);
        return;
      }
      _scheduleReconnect();
      return;
    }

    if (_disposed || _fatalAuth) return;

    // Handshake succeeded — reset attempt counter and mark connected.
    _attempt = 0;
    _setStatus(ConnectionStatus.connected);

    // Replay active subscriptions on every reconnect (i.e. every successful
    // connect *after* the first) so live streams don't go silent — but never
    // on the very first connect, since the notifiers' constructors already
    // subscribe once themselves.
    if (_everConnected) {
      for (final topic in _activeTopics) {
        transport.send(jsonEncode(ClientFrames.subscribe(topic)));
      }
    }
    _everConnected = true;

    _sub = transport.messageStream.listen(
      _handleMessage,
      onError: (Object error) {
        if (_disposed) return;
        if (_isAuthError(error)) {
          _fatalAuth = true;
          _setStatus(ConnectionStatus.disconnected);
          return;
        }
        _scheduleReconnect();
      },
      onDone: () {
        if (_disposed || _fatalAuth) return;
        _scheduleReconnect();
      },
      cancelOnError: false,
    );
  }

  void _handleMessage(dynamic message) {
    if (_frameController.isClosed) return;
    Map<String, dynamic>? json;
    try {
      if (message is String) {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic>) json = decoded;
      }
    } catch (_) {
      // Non-JSON message — fall through to MalformedFrame.
    }

    final frame = json != null
        ? BastionFrame.fromJson(json)
        : MalformedFrame(
            raw: const {},
            reason: 'non-JSON or non-object WebSocket message',
          );

    _frameController.add(frame);
  }

  /// Records a `subscribe`/`unsubscribe` frame in the active-subscription
  /// registry so it can be replayed on the next reconnect. No-op for any
  /// other frame kind, and safe if the payload/topic is missing or malformed
  /// (nothing to track).
  void _trackSubscription(Map<String, dynamic> json) {
    final kind = json['kind'];
    final payload = json['payload'];
    if (payload is! Map || payload['topic'] is! String) return;
    final topic = payload['topic'] as String;
    if (kind == 'subscribe') {
      _activeTopics.add(topic);
    } else if (kind == 'unsubscribe') {
      _activeTopics.remove(topic);
    }
  }

  /// Heuristic check for auth-related errors.
  bool _isAuthError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('401') ||
        msg.contains('unauthorized') ||
        msg.contains('forbidden');
  }

  void _scheduleReconnect() {
    if (_disposed || _fatalAuth) return;
    _setStatus(ConnectionStatus.reconnecting);
    final delay = _backoffSchedule(_attempt);
    _attempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_disposed || _fatalAuth) return;
      _setStatus(ConnectionStatus.connecting);
      _doConnect();
    });
  }
}
