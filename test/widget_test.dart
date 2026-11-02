// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:dotdigital_flutter_example/main.dart';
import 'package:dotdigital_flutter_example/screens/dashboard_screen.dart';
import 'package:dotdigital_flutter_example/services/notification_service.dart';
import 'package:dotdigital_flutter_example/theme/dotdigital_brand.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Uses platform system fonts for the brand theme', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final usesNamedFonts = platform == TargetPlatform.iOS ||
          platform == TargetPlatform.macOS ||
          platform == TargetPlatform.windows;
      final theme = DotdigitalBrand.buildTheme();
      expect(theme.textTheme.bodyMedium?.fontFamily, usesNamedFonts ? 'Arial' : 'sans-serif');
      expect(theme.appBarTheme.titleTextStyle?.fontFamily, usesNamedFonts ? 'Georgia' : 'serif');
      expect(DotdigitalBrand.headlineStyle().fontFamily, usesNamedFonts ? 'Georgia' : 'serif');
      expect(DotdigitalBrand.bodyStyle().fontFamily, usesNamedFonts ? 'Arial' : 'sans-serif');
    }
  });

  testWidgets('Dotdigital example app smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.dotdigital.push/methods'),
      (call) async => call.method == 'getNotificationPermissionStatus' ? 'notDetermined' : null,
    );
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const DotdigitalExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('MARKETING MADE HUMAN'), findsOneWidget);
    expect(find.text('Flutter push example app'), findsOneWidget);
    expect(find.text('Lifecycle Actions'), findsOneWidget);
    expect(find.text('Enable push'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Copies activity logs in display order and disables copying when empty', (tester) async {
    final service = NotificationService();
    service.clearLogs();
    addTearDown(service.clearLogs);
    String? copiedText;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    final copyButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Copy logs',
    );
    expect(tester.widget<IconButton>(copyButton).onPressed, isNull);

    service.triggerDeepLink('ddexample://first');
    service.triggerDeepLink('ddexample://second');
    await tester.pump();
    final expectedLogs = service.logs.join('\n');
    await tester.ensureVisible(copyButton);
    await tester.pumpAndSettle();
    await tester.tap(copyButton);
    await tester.pump();

    expect(copiedText, expectedLogs);
    expect(find.text('Activity logs copied to clipboard!'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(service.logs, isEmpty);
    expect(tester.widget<IconButton>(copyButton).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
