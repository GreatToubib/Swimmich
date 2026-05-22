import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/widgets/swimmich/undo_banner.dart';

Widget _host(VoidCallback onShow, VoidCallback onUndo) {
  return MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => showSwimmichUndoBanner(
          context,
          message: 'Photo deleted',
          onUndo: onUndo,
        ),
        child: const Text('DELETE'),
      ),
    ),
  );
}

void main() {
  group('showSwimmichUndoBanner', () {
    testWidgets('banner is visible at t=0 and undo is tappable', (tester) async {
      var undoCalled = false;
      await tester.pumpWidget(_host(() {}, () => undoCalled = true));

      await tester.tap(find.text('DELETE'));
      await tester.pump();

      expect(find.text('Photo deleted'), findsOneWidget);
      expect(find.text('UNDO'), findsOneWidget);

      await tester.tap(find.text('UNDO'));
      await tester.pump();

      expect(undoCalled, isTrue);
      expect(find.text('Photo deleted'), findsNothing);
    });

    testWidgets('banner still in tree at t=900ms (fading), removed at t=1100ms',
        (tester) async {
      await tester.pumpWidget(_host(() {}, () {}));

      await tester.tap(find.text('DELETE'));
      await tester.pump();

      expect(find.text('Photo deleted'), findsOneWidget);

      // Advance to 900ms — past the 800ms visible threshold, fade started.
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Photo deleted'), findsOneWidget);

      // Check IgnorePointer is active during fade — tap should not call undo.
      var undoCalledDuringFade = false;
      await tester.pumpWidget(_host(() {}, () => undoCalledDuringFade = true));
      // Re-show so the new callback is wired in.
      await tester.tap(find.text('DELETE'));
      await tester.pump(const Duration(milliseconds: 900));
      // Tapping UNDO during fade should be a no-op (IgnorePointer).
      await tester.tap(find.text('UNDO'), warnIfMissed: false);
      await tester.pump();
      expect(undoCalledDuringFade, isFalse);

      // Advance past the remove threshold (800+200=1000ms, we're at 900, need 200 more).
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('Photo deleted'), findsNothing);
    });

    testWidgets('undo at t=400ms fires callback and removes immediately',
        (tester) async {
      var undoCalled = false;
      await tester.pumpWidget(_host(() {}, () => undoCalled = true));

      await tester.tap(find.text('DELETE'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Photo deleted'), findsOneWidget);

      await tester.tap(find.text('UNDO'));
      await tester.pump();

      expect(undoCalled, isTrue);
      expect(find.text('Photo deleted'), findsNothing);
    });

    testWidgets('second show at t=400ms replaces first; first callback not called',
        (tester) async {
      var firstUndoCalled = false;
      var secondUndoCalled = false;

      // First show.
      await tester.pumpWidget(_host(() {}, () => firstUndoCalled = true));
      await tester.tap(find.text('DELETE'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Photo deleted'), findsOneWidget);

      // Second show — replaces the first.
      await tester.pumpWidget(_host(() {}, () => secondUndoCalled = true));
      await tester.tap(find.text('DELETE'));
      await tester.pump();

      // Only one banner in tree.
      expect(tester.widgetList(find.text('Photo deleted')).length, 1);
      expect(firstUndoCalled, isFalse);

      // Tapping undo calls the second callback only.
      await tester.tap(find.text('UNDO'));
      await tester.pump();

      expect(firstUndoCalled, isFalse);
      expect(secondUndoCalled, isTrue);
    });
  });
}
