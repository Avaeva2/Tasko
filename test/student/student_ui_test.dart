import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasko/student/student_app.dart';
import 'package:tasko/student/student_screens.dart';
import 'package:tasko/student/student_store.dart';

void main() {
  for (final width in [360.0, 1280.0]) {
    testWidgets('student shell has four working sections at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = StudentStore(persistDemo: false);
      await store.initialize();
      await store.enterDemo();
      if (width == 360) {
        await store.createSubject(
          name: 'Технологии разработки сложных программных систем и приложений',
        );
      }
      await tester.pumpWidget(StudentApp(store: store));
      await tester.pumpAndSettle();
      final month = const [
        'января',
        'февраля',
        'марта',
        'апреля',
        'мая',
        'июня',
        'июля',
        'августа',
        'сентября',
        'октября',
        'ноября',
        'декабря',
      ][DateTime.now().month - 1];
      expect(find.text(month), findsOneWidget);
      final nav = width < 1000
          ? find.byType(NavigationBar)
          : find.byType(NavigationRail);
      expect(nav, findsOneWidget);
      for (final label in ['Сегодня', 'Задания', 'Пары', 'Профиль']) {
        await tester.tap(find.descendant(of: nav, matching: find.text(label)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label at $width');
      }
      expect(find.text('Проекты'), findsNothing);
      expect(find.text('Команда'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    });
  }

  testWidgets(
    'kanban really scrolls to all three readable columns and search filters cards',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = StudentStore(persistDemo: false);
      await store.initialize();
      await store.enterDemo();
      await tester.pumpWidget(StudentApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Задания'),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(scroll, findsOneWidget);
      await tester.drag(scroll, const Offset(-580, 0));
      await tester.pumpAndSettle();
      expect(find.text('Готово').hitTestable(), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Поиск заданий'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('assignments-search')),
        'несуществующее задание',
      );
      await tester.pumpAndSettle();
      expect(find.text('Здесь пока нет заданий'), findsNWidgets(3));
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );

  testWidgets('subject editor validates and saves real store data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = StudentStore(persistDemo: false);
    await store.initialize();
    await store.enterDemo();
    late BuildContext routeContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              routeContext = context;
              return TextButton(
                onPressed: () => showStudySubjectEditor(context, store),
                child: const Text('Новый предмет'),
              );
            },
          ),
        ),
      ),
    );
    expect(routeContext.mounted, isTrue);
    await tester.tap(find.text('Новый предмет'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Введите название'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Физика');
    await tester.enterText(find.byType(TextFormField).last, 'Мария Иванова');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(
      store.subjects.any(
        (s) => s.name == 'Физика' && s.teacher == 'Мария Иванова',
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
