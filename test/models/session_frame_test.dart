import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/models/session_dto.dart';

void main() {
  // -------------------------------------------------------------------------
  // SessionDto / PaneDto
  // -------------------------------------------------------------------------
  group('SessionDto', () {
    test('fromJson decodes name/state/last_line', () {
      final dto = SessionDto.fromJson({
        'name': 'my-session',
        'state': 'running',
        'last_line': r'$ ',
      });
      expect(dto.name, 'my-session');
      expect(dto.state, 'running');
      expect(dto.lastLine, r'$ ');
    });

    test('toJson round-trips correctly', () {
      const dto = SessionDto(
        name: 'my-session',
        state: 'idle',
        lastLine: 'foo.txt',
      );
      final decoded = SessionDto.fromJson(dto.toJson());
      expect(decoded.name, dto.name);
      expect(decoded.state, dto.state);
      expect(decoded.lastLine, dto.lastLine);
    });

    test('missing last_line stays null and is omitted from toJson', () {
      final dto = SessionDto.fromJson({'name': 'x', 'state': 'idle'});
      expect(dto.lastLine, isNull);
      expect(dto.toJson().containsKey('last_line'), isFalse);
    });

    test('missing fields fall back to empty string', () {
      final dto = SessionDto.fromJson({});
      expect(dto.name, '');
      expect(dto.state, '');
    });
  });

  group('PaneDto', () {
    test('fromJson decodes session_name and lines', () {
      final dto = PaneDto.fromJson({
        'session_name': 'my-session',
        'lines': [r'$ ls', 'foo.txt'],
      });
      expect(dto.sessionName, 'my-session');
      expect(dto.lines, [r'$ ls', 'foo.txt']);
    });

    test('toJson round-trips correctly', () {
      const dto = PaneDto(sessionName: 'my-session', lines: ['a', 'b']);
      final decoded = PaneDto.fromJson(dto.toJson());
      expect(decoded.sessionName, dto.sessionName);
      expect(decoded.lines, dto.lines);
    });

    test('missing lines falls back to empty list', () {
      final dto = PaneDto.fromJson({'session_name': 'x'});
      expect(dto.lines, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // SessionsFrame
  // -------------------------------------------------------------------------
  group('SessionsFrame', () {
    test('fromJson decodes a list of sessions', () {
      final json = <String, dynamic>{
        'kind': 'sessions',
        'payload': {
          'sessions': [
            {'name': 'a', 'state': 'running'},
            {'name': 'b', 'state': 'idle', 'last_line': 'done'},
          ],
        },
      };
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<SessionsFrame>());
      final sessions = (frame as SessionsFrame).sessions;
      expect(sessions.length, 2);
      expect(sessions[0].name, 'a');
      expect(sessions[1].lastLine, 'done');
    });

    test('toJson round-trips correctly', () {
      const frame = SessionsFrame(
        sessions: [SessionDto(name: 'a', state: 'running')],
      );
      final decoded = BastionFrame.fromJson(frame.toJson());
      expect(decoded, isA<SessionsFrame>());
      expect((decoded as SessionsFrame).sessions.single.name, 'a');
    });

    test('empty sessions list decodes to an empty list, not malformed', () {
      final json = <String, dynamic>{
        'kind': 'sessions',
        'payload': {'sessions': <dynamic>[]},
      };
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<SessionsFrame>());
      expect((frame as SessionsFrame).sessions, isEmpty);
    });

    test('missing sessions list returns MalformedFrame', () {
      final json = <String, dynamic>{'kind': 'sessions', 'payload': {}};
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<MalformedFrame>());
    });
  });

  // -------------------------------------------------------------------------
  // PaneFrame
  // -------------------------------------------------------------------------
  group('PaneFrame', () {
    test('fromJson decodes session/seq/lines', () {
      final json = <String, dynamic>{
        'kind': 'pane',
        'payload': {
          'session': 'my-session',
          'seq': 3,
          'lines': [r'$ ls', 'foo.txt'],
        },
      };
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<PaneFrame>());
      final pane = frame as PaneFrame;
      expect(pane.session, 'my-session');
      expect(pane.seq, 3);
      expect(pane.lines, [r'$ ls', 'foo.txt']);
    });

    test('toJson round-trips correctly', () {
      const frame = PaneFrame(session: 's', seq: 1, lines: ['x']);
      final decoded = BastionFrame.fromJson(frame.toJson());
      expect(decoded, isA<PaneFrame>());
      final pane = decoded as PaneFrame;
      expect(pane.session, 's');
      expect(pane.seq, 1);
      expect(pane.lines, ['x']);
    });

    test('missing fields return MalformedFrame', () {
      final json = <String, dynamic>{
        'kind': 'pane',
        'payload': {'session': 's'},
      };
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<MalformedFrame>());
    });
  });

  // -------------------------------------------------------------------------
  // EventFrame
  // -------------------------------------------------------------------------
  group('EventFrame', () {
    test('needs_input payload decodes with session/event fields intact', () {
      final json = <String, dynamic>{
        'kind': 'event',
        'payload': {'session': 'my-session', 'event': 'needs_input'},
      };
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<EventFrame>());
      final event = frame as EventFrame;
      expect(event.session, 'my-session');
      expect(event.event, 'needs_input');
      expect(event.extra['session'], 'my-session');
      expect(event.extra['event'], 'needs_input');
    });

    test('unknown extra fields are preserved in extra map', () {
      final json = <String, dynamic>{
        'kind': 'event',
        'payload': {
          'session': 's',
          'event': 'needs_input',
          'reason': 'blocked-on-prompt',
        },
      };
      final frame = BastionFrame.fromJson(json) as EventFrame;
      expect(frame.extra['reason'], 'blocked-on-prompt');
    });

    test('toJson round-trips correctly', () {
      const frame = EventFrame(
        session: 's',
        event: 'needs_input',
        extra: {'session': 's', 'event': 'needs_input'},
      );
      final decoded = BastionFrame.fromJson(frame.toJson());
      expect(decoded, isA<EventFrame>());
      final event = decoded as EventFrame;
      expect(event.session, 's');
      expect(event.event, 'needs_input');
    });

    test('missing session/event returns MalformedFrame', () {
      final json = <String, dynamic>{
        'kind': 'event',
        'payload': {'event': 'needs_input'},
      };
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<MalformedFrame>());
    });
  });

  // -------------------------------------------------------------------------
  // Client->server encoders
  // -------------------------------------------------------------------------
  group('ClientFrames', () {
    test('subscribe encodes topic', () {
      final json = ClientFrames.subscribe('sessions');
      expect(json['kind'], 'subscribe');
      expect(json['payload'], {'topic': 'sessions'});
    });

    test('subscribe encodes pane topic', () {
      final json = ClientFrames.subscribe('pane:my-session');
      expect(json['payload'], {'topic': 'pane:my-session'});
    });

    test('unsubscribe encodes topic', () {
      final json = ClientFrames.unsubscribe('sessions');
      expect(json['kind'], 'unsubscribe');
      expect(json['payload'], {'topic': 'sessions'});
    });

    test('send encodes session and keys', () {
      final json = ClientFrames.send(session: 'my-session', keys: 'y\n');
      expect(json['kind'], 'send');
      expect(json['payload'], {'session': 'my-session', 'keys': 'y\n'});
    });

    test('sendKey encodes session and key', () {
      final json = ClientFrames.sendKey(session: 'my-session', key: 'Enter');
      expect(json['kind'], 'send_key');
      expect(json['payload'], {'session': 'my-session', 'key': 'Enter'});
    });
  });

  // -------------------------------------------------------------------------
  // Unknown kind still falls through unaffected by new v0.2 kinds
  // -------------------------------------------------------------------------
  group('UnknownFrame — forward compatibility unaffected by v0.2 kinds', () {
    test('a still-unmodeled kind returns UnknownFrame', () {
      final json = <String, dynamic>{
        'kind': 'repo_status',
        'payload': {'ok': true},
      };
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<UnknownFrame>());
    });
  });
}
