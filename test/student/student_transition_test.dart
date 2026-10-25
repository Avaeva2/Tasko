import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasko/student/student_motion.dart';
import 'package:tasko/student/student_theme.dart';

void main() {
  testWidgets(
    'nested routes slide as opaque pages instead of fading text together',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudentTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  StudentRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: Text('Детали задания')),
                  ),
                ),
                child: const Text('Открыть задание'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть задание'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final text = find.text('Детали задания');
      expect(
        find.ancestor(of: text, matching: find.byType(FadeTransition)),
        findsNothing,
      );
      expect(
        find.ancestor(of: text, matching: find.byType(SlideTransition)),
        findsWidgets,
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(
        find.ancestor(of: text, matching: find.byType(FadeTransition)),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(find.text('Открыть задание'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'only the selected section paints during rapid transitions (reduced=$reduced)',
      (tester) async {
        final selected = ValueNotifier<int>(0);
        final text = TextEditingController(text: 'Сохранённый черновик');
        addTearDown(selected.dispose);
        addTearDown(text.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: ValueListenableBuilder<int>(
                  valueListenable: selected,
                  builder: (context, index, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      StudentSectionScene(
                        key: const ValueKey('first-section'),
                        active: index == 0,
                        direction: 1,
                        child: Column(
                          children: [
                            const Text('Первый экран'),
                            TextField(controller: text),
                          ],
                        ),
                      ),
                      StudentSectionScene(
                        key: const ValueKey('second-section'),
                        active: index == 1,
                        direction: 1,
                        child: const Text('Второй экран'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final target in [1, 0, 1, 0, 1]) {
          selected.value = target;
          await tester.pump();
          // Sample the actual intermediate frames, rather than just the settled UI.
          for (var frame = 0; frame < 7; frame++) {
            expect(
              find.text(target == 1 ? 'Первый экран' : 'Второй экран'),
              findsNothing,
            );
            expect(
              find.text(target == 1 ? 'Второй экран' : 'Первый экран'),
              findsOneWidget,
            );
            expect(
              find.text(
                target == 1 ? 'Первый экран' : 'Второй экран',
                skipOffstage: false,
              ),
              findsOneWidget,
              reason: 'Inactive content must stay mounted to retain forms and scroll positions.',
            );
            await tester.pump(const Duration(milliseconds: 12));
          }
        }
        selected.value = 0;
        await tester.pumpAndSettle();
        expect(find.text('Сохранённый черновик'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
