import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/action_dto.dart';

void main() {
  // -------------------------------------------------------------------------
  // CommandRequest
  // -------------------------------------------------------------------------
  group('CommandRequest', () {
    test('inject round-trip: emits mode/session/command only', () {
      const request = CommandRequest(
        mode: CommandMode.inject,
        session: 'main',
        command: '/status',
      );
      final json = request.toJson();

      expect(json['mode'], 'inject');
      expect(json['session'], 'main');
      expect(json['command'], '/status');
      expect(json.containsKey('name'), isFalse);
      expect(json.containsKey('dir'), isFalse);
      expect(json.containsKey('model'), isFalse);
    });

    test('spawn round-trip with dir+model: all fields present', () {
      const request = CommandRequest(
        mode: CommandMode.spawn,
        name: 'work',
        dir: '/repo',
        model: CommandModel.opus,
        command: '/status',
      );
      final json = request.toJson();

      expect(json['mode'], 'spawn');
      expect(json['name'], 'work');
      expect(json['dir'], '/repo');
      expect(json['model'], 'opus');
      expect(json['command'], '/status');
      expect(json.containsKey('session'), isFalse);
    });

    test('spawn with dir/model omitted: keys are absent, not null', () {
      const request = CommandRequest(
        mode: CommandMode.spawn,
        name: 'work',
        command: '/status',
      );
      final json = request.toJson();

      expect(json.containsKey('dir'), isFalse);
      expect(json.containsKey('model'), isFalse);
      expect(json.containsKey('session'), isFalse);
      expect(json['name'], 'work');
    });

    test('inject request never emits a name key even if set', () {
      const request = CommandRequest(
        mode: CommandMode.inject,
        session: 'main',
        name: 'ignored',
        command: '/status',
      );
      final json = request.toJson();

      expect(json.containsKey('name'), isFalse);
      expect(json['session'], 'main');
    });

    test('value equality', () {
      const a = CommandRequest(
        mode: CommandMode.inject,
        session: 'main',
        command: '/status',
      );
      const b = CommandRequest(
        mode: CommandMode.inject,
        session: 'main',
        command: '/status',
      );
      const c = CommandRequest(
        mode: CommandMode.inject,
        session: 'other',
        command: '/status',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // CommandResponse
  // -------------------------------------------------------------------------
  group('CommandResponse', () {
    test('fromJson decodes session', () {
      final response = CommandResponse.fromJson(const {'session': 'work'});
      expect(response.session, 'work');
    });

    test('toJson round-trips correctly', () {
      const response = CommandResponse(session: 'work');
      final decoded = CommandResponse.fromJson(response.toJson());
      expect(decoded.session, response.session);
    });

    test('missing session falls back to empty string', () {
      final response = CommandResponse.fromJson(const {});
      expect(response.session, '');
    });

    test('value equality', () {
      const a = CommandResponse(session: 'work');
      const b = CommandResponse(session: 'work');
      const c = CommandResponse(session: 'other');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
