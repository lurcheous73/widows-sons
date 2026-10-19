import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widows_sons/main.dart';

import 'support.dart';

void main() {
  test('event dates retain the chapter clock and offset', () {
    expect(eventDate('2099-07-01T10:00:00+01:00'), contains('10:00 UTC+01:00'));
    expect(eventDate('2099-01-01T10:00:00+00:00'), contains('10:00 GMT'));
  });

  testWidgets('chapter to news to article is a complete reading flow', (
    tester,
  ) async {
    final state = fixtureState();
    await tester.pumpWidget(WidowsSonsApp(state: state));
    expect(find.text('Good roads.\nBetter company.'), findsOneWidget);
    await tester.tap(find.text('News').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('No matching stories.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('A new home for chapter news.'));
    await tester.pumpAndSettle();
    expect(
      find.text('Welcome to the chapter.\n\nAnother paragraph.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('member invitation validates locally before a request', (
    tester,
  ) async {
    await tester.pumpWidget(WidowsSonsApp(state: fixtureState()));
    await tester.tap(find.text('Member').last);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Activate my membership')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activate my membership'));
    await tester.pumpAndSettle();
    expect(
      find.text('Paste the complete invitation from your chapter.'),
      findsOneWidget,
    );
  });

  testWidgets('no published rides displays an honest empty state', (
    tester,
  ) async {
    await tester.pumpWidget(WidowsSonsApp(state: fixtureState()));
    await tester.tap(find.text('Rides').last);
    await tester.pumpAndSettle();
    expect(find.text('See you on the next one.'), findsOneWidget);
    expect(find.text('Test chapter ride'), findsNothing);
  });

  testWidgets('published event opens its details and invitation guidance', (
    tester,
  ) async {
    await tester.pumpWidget(WidowsSonsApp(state: fixtureState(events: true)));
    await tester.tap(find.text('Rides').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test chapter ride'));
    await tester.pumpAndSettle();
    expect(find.text('Test route details'), findsOneWidget);
    expect(find.textContaining('Activate your membership'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 430.0, 1024.0]) {
    testWidgets('navigation and content fit width $width with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(WidowsSonsApp(state: fixtureState()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final name in ['Rides', 'News', 'Member']) {
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
    'populated rides and member card fit a narrow phone with double text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        WidowsSonsApp(state: fixtureState(events: true, member: true)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final name in ['Rides', 'Member']) {
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
