import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/models/dto.dart';

void main() {
  // -------------------------------------------------------------------------
  // EchoFrame
  // -------------------------------------------------------------------------
  group('EchoFrame', () {
    test('fromJson decodes an echo frame', () {
      final json = <String, dynamic>{
        'kind': 'echo',
        'payload': {'msg': 'hello'},
      };
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<EchoFrame>());
      final echo = frame as EchoFrame;
      expect(echo.kind, 'echo');
      expect((echo.payload as Map)['msg'], 'hello');
    });

    test('toJson round-trips correctly', () {
      const frame = EchoFrame(payload: {'x': 1});
      final json = frame.toJson();
      expect(json['kind'], 'echo');
      expect((json['payload'] as Map)['x'], 1);

      final decoded = BastionFrame.fromJson(json);
      expect(decoded, isA<EchoFrame>());
    });

    test('echo with null payload round-trips', () {
      const frame = EchoFrame(payload: null);
      final json = frame.toJson();
      final decoded = BastionFrame.fromJson(json);
      expect(decoded, isA<EchoFrame>());
      expect((decoded as EchoFrame).payload, isNull);
    });

    test('echo with string payload round-trips', () {
      const frame = EchoFrame(payload: 'ping');
      final json = frame.toJson();
      final decoded = BastionFrame.fromJson(json);
      expect(decoded, isA<EchoFrame>());
      expect((decoded as EchoFrame).payload, 'ping');
    });
  });

  // -------------------------------------------------------------------------
  // ErrorFrame
  // -------------------------------------------------------------------------
  group('ErrorFrame', () {
    test('fromJson decodes an error frame with code and message', () {
      final json = <String, dynamic>{
        'kind': 'error',
        'payload': {'code': 'unauthorized', 'message': 'token missing'},
      };
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<ErrorFrame>());
      final err = frame as ErrorFrame;
      expect(err.payload.code, 'unauthorized');
      expect(err.payload.message, 'token missing');
    });

    test('fromJson decodes an error frame with code only', () {
      final json = <String, dynamic>{
        'kind': 'error',
        'payload': {'code': 'not_found'},
      };
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<ErrorFrame>());
      expect((frame as ErrorFrame).payload.code, 'not_found');
      expect(frame.payload.message, isNull);
    });

    test('toJson round-trips correctly', () {
      final frame = ErrorFrame(
        payload: const ErrorPayloadFrame(
          code: 'unauthorized',
          message: 'token missing',
        ),
      );
      final json = frame.toJson();
      expect(json['kind'], 'error');
      final decoded = BastionFrame.fromJson(json);
      expect(decoded, isA<ErrorFrame>());
      final decodedErr = decoded as ErrorFrame;
      expect(decodedErr.payload.code, 'unauthorized');
      expect(decodedErr.payload.message, 'token missing');
    });

    test('error frame with non-object payload returns MalformedFrame', () {
      final json = <String, dynamic>{'kind': 'error', 'payload': 'bad-payload'};
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<MalformedFrame>());
    });
  });

  // -------------------------------------------------------------------------
  // Unknown kind — forward compatibility
  // -------------------------------------------------------------------------
  group('UnknownFrame', () {
    test('unknown kind does not throw — returns UnknownFrame', () {
      final json = <String, dynamic>{
        'kind': 'session_update',
        'payload': {'id': '123'},
      };
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<UnknownFrame>());
      final unknown = frame as UnknownFrame;
      expect(unknown.kind, 'session_update');
      expect((unknown.payload as Map)['id'], '123');
    });

    test('UnknownFrame toJson preserves kind and payload', () {
      const frame = UnknownFrame(kind: 'future_kind', payload: 42);
      final json = frame.toJson();
      expect(json['kind'], 'future_kind');
      expect(json['payload'], 42);
    });
  });

  // -------------------------------------------------------------------------
  // Malformed input
  // -------------------------------------------------------------------------
  group('MalformedFrame', () {
    test('missing kind field returns MalformedFrame', () {
      final json = <String, dynamic>{'payload': 'oops'};
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<MalformedFrame>());
      expect((frame as MalformedFrame).reason, contains('kind'));
    });

    test('non-string kind returns MalformedFrame', () {
      final json = <String, dynamic>{'kind': 99, 'payload': null};
      final frame = BastionFrame.fromJson(json);
      expect(frame, isA<MalformedFrame>());
    });
  });

  // -------------------------------------------------------------------------
  // ErrorPayloadFrame unit
  // -------------------------------------------------------------------------
  group('ErrorPayloadFrame', () {
    test('fromJson decodes code and message', () {
      final ep = ErrorPayloadFrame.fromJson({
        'code': 'unauthorized',
        'message': 'bad token',
      });
      expect(ep.code, 'unauthorized');
      expect(ep.message, 'bad token');
    });

    test('missing code falls back gracefully', () {
      final ep = ErrorPayloadFrame.fromJson({'message': 'no code here'});
      expect(ep.code, 'unknown');
      expect(ep.message, contains('malformed'));
    });

    test('toJson omits null message', () {
      const ep = ErrorPayloadFrame(code: 'not_found');
      final json = ep.toJson();
      expect(json.containsKey('message'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // HealthDto
  // -------------------------------------------------------------------------
  group('HealthDto', () {
    test('fromJson decodes status and service', () {
      final dto = HealthDto.fromJson({'status': 'ok', 'service': 'bastion'});
      expect(dto.status, 'ok');
      expect(dto.service, 'bastion');
    });

    test('toJson round-trips correctly', () {
      const dto = HealthDto(status: 'ok', service: 'bastion');
      final json = dto.toJson();
      expect(json['status'], 'ok');
      expect(json['service'], 'bastion');
      final decoded = HealthDto.fromJson(json);
      expect(decoded.status, 'ok');
      expect(decoded.service, 'bastion');
    });

    test('missing fields fall back to empty string', () {
      final dto = HealthDto.fromJson({});
      expect(dto.status, '');
      expect(dto.service, '');
    });
  });

  // -------------------------------------------------------------------------
  // ErrorPayload (REST DTO)
  // -------------------------------------------------------------------------
  group('ErrorPayload (REST DTO)', () {
    test('fromJson decodes 401 shape', () {
      final ep = ErrorPayload.fromJson({
        'error': 'unauthorized',
        'code': 'unauthorized',
      });
      expect(ep.error, 'unauthorized');
      expect(ep.code, 'unauthorized');
      expect(ep.message, isNull);
    });

    test('toJson omits null fields', () {
      const ep = ErrorPayload(code: 'unauthorized');
      final json = ep.toJson();
      expect(json.containsKey('error'), isFalse);
      expect(json.containsKey('message'), isFalse);
      expect(json['code'], 'unauthorized');
    });

    test('round-trips with all fields', () {
      const ep = ErrorPayload(
        error: 'unauthorized',
        code: 'unauthorized',
        message: 'bad token',
      );
      final decoded = ErrorPayload.fromJson(ep.toJson());
      expect(decoded.error, ep.error);
      expect(decoded.code, ep.code);
      expect(decoded.message, ep.message);
    });

    test('missing code falls back to unknown', () {
      final ep = ErrorPayload.fromJson({'error': 'something'});
      expect(ep.code, 'unknown');
    });
  });
}
