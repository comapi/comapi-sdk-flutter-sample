import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dotdigital_push/dotdigital_push.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ending a session sends only the session-ending platform call', () async {
    const channel = MethodChannel('com.dotdigital.push/methods');
    final calls = <String>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(await DotdigitalPush.endSession(), isTrue);
    expect(calls, ['endSession']);
  });

  group('DotdigitalConfig & JWT Generation Tests', () {
    test('generateJwt creates valid HS256 JWT with required claims', () {
      const config = DotdigitalConfig(
        apiSpaceId: 'test-space-id',
        sharedSecret: 'test-secret-key-12345',
        issuer: 'https://api.comapi.com/defaultauth',
        audience: 'https://api.comapi.com',
        userId: 'test_user_999',
        contactEmail: 'tester@example.com',
      );

      final token = config.generateJwt(nonce: 'sample-nonce-abc-123');
      final parts = token.split('.');
      expect(parts.length, equals(3));

      // Decode header
      final headerJson = utf8.decode(base64Url.decode(base64Url.normalize(parts[0])));
      final header = jsonDecode(headerJson) as Map<String, dynamic>;
      expect(header['alg'], equals('HS256'));
      expect(header['typ'], equals('JWT'));

      // Decode payload
      final payloadJson = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      expect(payload['nonce'], equals('sample-nonce-abc-123'));
      expect(payload['sub'], equals('test_user_999'));
      expect(payload['iss'], equals('https://api.comapi.com/defaultauth'));
      expect(payload['aud'], equals('https://api.comapi.com'));
      expect(payload['iat'], isA<int>());
      expect(payload['exp'], isA<int>());
    });

    test('PushNotification fromMap deserialization', () {
      final map = {
        'title': 'Sale Alert',
        'body': 'Check out 50% off deals',
        'deepLinkUrl': 'ddexample://promo',
        'customData': {'promoId': '50off'},
        'rawPayload': {'key': 'val'},
        'timestamp': 1700000000000,
      };

      final notification = PushNotification.fromMap(map);
      expect(notification.title, equals('Sale Alert'));
      expect(notification.body, equals('Check out 50% off deals'));
      expect(notification.deepLinkUrl, equals('ddexample://promo'));
      expect(notification.customData?['promoId'], equals('50off'));
    });

    test('PushTapEvent fromMap deserialization', () {
      final map = {
        'url': 'ddexample://product/42',
        'customData': {'category': 'footwear'},
        'isClickRecorded': true,
        'isDeepLinkCalled': true,
        'isDdOriginated': true,
        'rawPayload': {'foo': 'bar'},
      };

      final tap = PushTapEvent.fromMap(map);
      expect(tap.url, equals('ddexample://product/42'));
      expect(tap.isClickRecorded, isTrue);
      expect(tap.isDeepLinkCalled, isTrue);
      expect(tap.isDdOriginated, isTrue);
    });
  });
}
