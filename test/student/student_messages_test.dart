import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasko/student/student_widgets.dart';

void main() {
  for (final action in [false, true]) {
    testWidgets(
      'student notice expires with action=$action and accessibility enabled',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(accessibleNavigation: true),
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showStudentMessage(
                      context,
                      'Изменение сохранено',
                      action: action
                          ? SnackBarAction(label: 'Отменить', onPressed: () {})
                          : null,
                    ),
                    child: const Text('Показать'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Показать'));
        await tester.pumpAndSettle();
        expect(find.text('Изменение сохранено'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(SnackBar), findsOneWidget);
        await tester.pump(Duration(seconds: action ? 4 : 2));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }
  testWidgets('new notice replaces the old one instead of forming a queue', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showStudentMessage(context, 'Сохранено ${++count}'),
              child: const Text('Показать'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Показать'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Показать'));
    await tester.pumpAndSettle();
    expect(find.text('Сохранено 1'), findsNothing);
    expect(find.text('Сохранено 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
