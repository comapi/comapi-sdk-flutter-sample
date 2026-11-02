import 'dart:convert';

import 'package:dotdigital_flutter_example/services/notification_service.dart';
import 'package:dotdigital_push/dotdigital_push.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.dotdigital.push/methods');
  final calls = <String>[];
  var permission = 'authorized';
  var active = false;
  var endSucceeds = true;
  var syncSucceeds = true;
  var initializeSucceeds = true;
  PlatformException? startError;
  var profileId = 'user-1';

  const config = DotdigitalConfig(
    apiSpaceId: 'space-1',
    userId: 'user-1',
    sharedSecret: 'test-secret',
    contactEmail: 'user@example.com',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    permission = 'authorized';
    active = false;
    endSucceeds = true;
    syncSucceeds = true;
    initializeSucceeds = true;
    startError = null;
    profileId = 'user-1';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getNotificationPermissionStatus':
          return permission;
        case 'initialize':
          return initializeSucceeds;
        case 'registerPushToken':
          return true;
        case 'requestNotificationPermissions':
          permission = 'authorized';
          return true;
        case 'getSessionState':
          return {'isSessionActive': active, 'profileId': active ? profileId : null};
        case 'startSession':
          if (startError != null) throw startError!;
          active = true;
          return true;
        case 'endSession':
          if (endSucceeds) active = false;
          return endSucceeds;
        case 'updateUserEmail':
          return syncSucceeds;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<NotificationService> createService({bool configure = false}) async {
    final service = NotificationService.forTesting();
    await service.init();
    if (configure) expect(await service.saveConfiguration(config), isTrue);
    return service;
  }

  test('unconfigured app can be configured after enable is attempted', () async {
    final service = await createService();
    expect(await service.enablePush(), isFalse);
    expect(service.lifecycleError, contains('Configure an API space and user'));
    expect(service.needsConfirmation, isTrue);
    expect(calls, isNot(contains('initialize')));
    expect(await service.saveConfiguration(config), isTrue);
    expect(await service.enablePush(), isTrue);
    service.dispose();
  });

  test('first use requires consent and syncs once', () async {
    final service = await createService(configure: true);
    permission = 'notDetermined';
    expect(await service.startLifecycle(), isTrue);
    expect(calls, isNot(contains('initialize')));
    expect(await service.enablePush(), isTrue);
    expect(service.isEmailSynced, isTrue);
    expect(calls.where((call) => call == 'requestNotificationPermissions'), hasLength(1));
    expect(calls.where((call) => call == 'startSession'), hasLength(1));
    expect(calls.where((call) => call == 'updateUserEmail'), hasLength(1));
    service.dispose();
  });

  test('late native token updates session state without logging the token', () async {
    final service = await createService(configure: true);
    expect(await service.enablePush(), isTrue);
    expect(service.sessionState.pushToken, isNull);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'com.dotdigital.push/methods',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('onPushTokenReceived', 'test-push-token')),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.sessionState.pushToken, 'test-push-token');
    expect(service.hasMatchingSession, isTrue);
    expect(service.logs.first, contains('Device push token received.'));
    expect(service.logs.first, isNot(contains('test-push-token')));
    service.dispose();
  });

  test('session failure after challenge explains authentication configuration', () async {
    final service = await createService(configure: true);
    startError = PlatformException(code: 'START_SESSION_FAILED', details: {
      'domain': 'com.comapi.foundation.request.template',
      'code': 5554,
      'challengeReceived': true,
    });
    expect(await service.enablePush(), isFalse);
    expect(service.logs.first, contains('after the authentication challenge'));
    expect(service.logs.first, contains('Shared Secret, Issuer, Audience, and ID claim'));
    expect(service.logs.first, contains('did not provide the HTTP status'));
    expect(service.logs.first, isNot(contains('test-secret')));
    service.dispose();
  });

  test('session network failure reports its code without exposing error details', () async {
    final service = await createService(configure: true);
    startError = PlatformException(code: 'START_SESSION_FAILED', message: 'sensitive details', details: {
      'domain': 'com.comapi.foundation.request.template',
      'code': 5554,
      'challengeReceived': false,
      'underlyingDomain': 'NSURLErrorDomain',
      'underlyingCode': -1009,
    });
    expect(await service.enablePush(), isFalse);
    expect(service.logs.first, contains('network error (code -1009)'));
    expect(service.logs.first, isNot(contains('sensitive details')));
    service.dispose();
  });

  test('unsupported session URL identifies the SDK endpoint configuration', () async {
    final service = await createService(configure: true);
    startError = PlatformException(code: 'START_SESSION_FAILED', details: {
      'domain': 'com.comapi.foundation.request.template',
      'code': 5554,
      'challengeReceived': false,
      'underlyingDomain': 'NSURLErrorDomain',
      'underlyingCode': -1002,
    });
    expect(await service.enablePush(), isFalse);
    expect(service.logs.first, contains('URL is invalid or unsupported'));
    expect(service.logs.first, contains('SDK API endpoint configuration'));
    service.dispose();
  });

  test('session challenge failure and legacy errors explain missing HTTP status', () async {
    final service = await createService(configure: true);
    startError = PlatformException(code: 'START_SESSION_FAILED', details: {
      'domain': 'com.comapi.foundation.request.template',
      'code': 5554,
      'challengeReceived': false,
    });
    expect(await service.enablePush(), isFalse);
    expect(service.logs.first, contains('before authentication'));
    expect(service.logs.first, contains('API Space ID'));
    startError = PlatformException(
      code: 'START_SESSION_FAILED',
      message: 'The operation couldn’t be completed. (com.comapi.foundation.request.template error 5554.)',
    );
    expect(await service.retryLifecycle(), isFalse);
    expect(service.logs.first, contains('unexpected response or network error'));
    expect(service.logs.first, contains('did not provide the HTTP status'));
    service.dispose();
  });

  test('returning user reuses an active session without prompting or syncing', () async {
    final first = await createService(configure: true);
    expect(await first.enablePush(), isTrue);
    first.dispose();
    calls.clear();
    final returning = await createService();
    expect(await returning.startLifecycle(), isTrue);
    expect(calls, contains('initialize'));
    expect(calls, contains('registerPushToken'));
    expect(calls, isNot(contains('startSession')));
    expect(calls, isNot(contains('requestNotificationPermissions')));
    expect(calls, isNot(contains('updateUserEmail')));
    returning.dispose();
  });

  test('returning user starts an inactive session without resyncing email', () async {
    final first = await createService(configure: true);
    await first.enablePush();
    first.dispose();
    active = false;
    calls.clear();
    final returning = await createService();
    expect(await returning.startLifecycle(), isTrue);
    expect(calls.where((call) => call == 'startSession'), hasLength(1));
    expect(calls, isNot(contains('updateUserEmail')));
    returning.dispose();
  });

  test('permission revoked prevents new session on startup', () async {
    final first = await createService(configure: true);
    await first.enablePush();
    first.dispose();
    active = false;
    permission = 'denied';
    calls.clear();
    final returning = await createService();
    expect(await returning.startLifecycle(), isTrue);
    expect(returning.permissionStatus, PushPermissionStatus.denied);
    expect(calls, isNot(contains('initialize')));
    expect(calls, isNot(contains('startSession')));
    expect(calls, isNot(contains('requestNotificationPermissions')));
    returning.dispose();
  });

  test('failed email sync is retried and not marked complete', () async {
    final service = await createService(configure: true);
    syncSucceeds = false;
    expect(await service.enablePush(), isFalse);
    expect(service.isEmailSynced, isFalse);
    syncSucceeds = true;
    expect(await service.retryLifecycle(), isTrue);
    expect(service.isEmailSynced, isTrue);
    expect(calls.where((call) => call == 'updateUserEmail'), hasLength(2));
    service.dispose();
  });

  test('opt-out persists and failed teardown cannot restart the session', () async {
    final first = await createService(configure: true);
    await first.enablePush();
    endSucceeds = false;
    expect(await first.endSession(), isFalse);
    expect(first.isOptOutPending, isTrue);
    first.dispose();
    calls.clear();
    final returning = await createService();
    expect(await returning.startLifecycle(), isFalse);
    expect(calls.indexOf('initialize'), lessThan(calls.indexOf('endSession')));
    expect(calls, isNot(contains('startSession')));
    endSucceeds = true;
    expect(await returning.retryLifecycle(), isTrue);
    returning.dispose();
    calls.clear();
    final optedOut = await createService();
    await optedOut.startLifecycle();
    expect(optedOut.isPushEnabled, isFalse);
    expect(calls, isNot(contains('initialize')));
    expect(calls, isNot(contains('startSession')));
    optedOut.dispose();
  });

  test('user change is blocked when old session cannot be ended', () async {
    final service = await createService(configure: true);
    await service.enablePush();
    endSucceeds = false;
    expect(await service.saveConfiguration(const DotdigitalConfig(apiSpaceId: 'space-1', userId: 'user-2')), isFalse);
    expect(service.config.userId, 'user-1');
    expect(service.isOptOutPending, isTrue);
    service.dispose();
  });

  test('restored session for a different user is not accepted', () async {
    final first = await createService(configure: true);
    await first.enablePush();
    first.dispose();
    profileId = 'different-user';
    calls.clear();
    final returning = await createService();
    expect(await returning.startLifecycle(), isFalse);
    expect(returning.lifecycleError, contains('another user'));
    expect(calls, isNot(contains('startSession')));
    returning.dispose();
  });

  test('changing email syncs once and changing user requires fresh consent', () async {
    final service = await createService(configure: true);
    await service.enablePush();
    calls.clear();
    expect(await service.saveConfiguration(const DotdigitalConfig(
      apiSpaceId: 'space-1', userId: 'user-1', sharedSecret: 'test-secret', contactEmail: 'new@example.com',
    )), isTrue);
    expect(calls.where((call) => call == 'updateUserEmail'), hasLength(1));
    expect(service.isEmailSynced, isTrue);
    calls.clear();
    expect(await service.saveConfiguration(const DotdigitalConfig(
      apiSpaceId: 'space-1', userId: 'user-2', sharedSecret: 'test-secret', contactEmail: 'new@example.com',
    )), isTrue);
    expect(calls, contains('endSession'));
    expect(calls, isNot(contains('startSession')));
    expect(service.needsConfirmation, isTrue);
    expect(service.isEmailSynced, isFalse);
    service.dispose();
  });

  test('switching users reuses the SDK and signs challenges for the new user', () async {
    final service = await createService(configure: true);
    expect(await service.enablePush(), isTrue);
    calls.clear();
    expect(await service.saveConfiguration(const DotdigitalConfig(
      apiSpaceId: 'space-1', userId: 'user-2', sharedSecret: 'new-secret',
    )), isTrue);
    expect(calls, contains('endSession'));
    expect(service.restartRequired, isFalse);
    profileId = 'user-2';
    calls.clear();
    expect(await service.enablePush(), isTrue);
    expect(calls, isNot(contains('initialize')));
    expect(service.hasMatchingSession, isTrue);

    String? jwt;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'com.dotdigital.push/methods',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onAuthenticationChallenge', {'nonce': 'new-nonce'}),
      ),
      (reply) => jwt = const StandardMethodCodec().decodeEnvelope(reply!) as String?,
    );
    final payload = jwt!.split('.')[1];
    final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload)))) as Map;
    expect(claims['sub'], 'user-2');
    expect(claims['nonce'], 'new-nonce');
    service.dispose();
  });

  test('changing the API space ends the session and requires an app restart', () async {
    final service = await createService(configure: true);
    expect(await service.enablePush(), isTrue);
    calls.clear();
    expect(await service.saveConfiguration(const DotdigitalConfig(
      apiSpaceId: 'space-2', userId: 'user-2', sharedSecret: 'test-secret',
    )), isTrue);
    expect(calls, contains('endSession'));
    expect(calls, isNot(contains('initialize')));
    expect(service.restartRequired, isTrue);
    expect(service.isInitialized, isFalse);
    expect(service.needsConfirmation, isTrue);
    calls.clear();
    expect(await service.enablePush(), isFalse);
    expect(service.lifecycleError, contains('Restart the app'));
    expect(service.needsConfirmation, isTrue);
    expect(calls, isNot(contains('startSession')));
    service.dispose();

    final restarted = await createService();
    expect(restarted.config.apiSpaceId, 'space-2');
    expect(restarted.restartRequired, isFalse);
    profileId = 'user-2';
    expect(await restarted.enablePush(), isTrue);
    expect(calls, contains('initialize'));
    expect(restarted.hasMatchingSession, isTrue);
    restarted.dispose();
  });

  test('permission restored in settings resumes the session without prompting', () async {
    final service = await createService(configure: true);
    permission = 'denied';
    expect(await service.enablePush(), isTrue);
    expect(calls, isNot(contains('startSession')));
    permission = 'authorized';
    calls.clear();
    expect(await service.startLifecycle(), isTrue);
    expect(calls, contains('startSession'));
    expect(calls, isNot(contains('requestNotificationPermissions')));
    service.dispose();
  });

  test('failed initialization reports an error and retry starts once', () async {
    final service = await createService(configure: true);
    initializeSucceeds = false;
    expect(await service.enablePush(), isFalse);
    expect(service.lifecycleError, contains('initialization failed'));
    expect(calls, isNot(contains('startSession')));
    initializeSucceeds = true;
    expect(await service.retryLifecycle(), isTrue);
    expect(calls.where((call) => call == 'startSession'), hasLength(1));
    service.dispose();
  });
}