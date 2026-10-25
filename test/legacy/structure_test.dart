import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/legacy_main.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/ui/core_screens.dart';
import 'package:tasko/legacy/ui/secondary_screens.dart';
import 'package:tasko/legacy/ui/task_detail_screen.dart';
import 'package:tasko/legacy/ui/timeline_screen.dart';

Future<TaskoStore> demo() async {
  final store = TaskoStore(persistDemo: false);
  await store.initialize();
  await store.enterDemo();
  return store;
}

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'Compact board keeps navigation and avatar opens profile directly',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await demo();
      addTearDown(store.dispose);
      await tester.pumpWidget(TaskoApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Профиль'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Проекты'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.projects.first.name));
      await tester.pumpAndSettle();
      expect(find.byType(BoardScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.byType(ProjectsScreen), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Задачи'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Calendar creation uses selected day and shows the saved task', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final store = await demo();
    addTearDown(store.dispose);
    store.tasks = [];
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day == 1 ? 2 : 1);
    await tester.pumpWidget(TaskoApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Календарь и отчёты'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Календарь'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${date.day}'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(TextButton, 'Создать задачу'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Создать задачу'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Задача выбранного дня',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать задачу'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.dueDate, date);
    expect(find.text('Задача выбранного дня'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Expanded sidebar keeps project board and opens task pane', (
    tester,
  ) async {
    viewport(tester, const Size(1440, 900));
    final store = await demo();
    addTearDown(store.dispose);
    await tester.pumpWidget(TaskoApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text(store.projects.first.name).first);
    await tester.pumpAndSettle();
    expect(find.text('Мои задачи'), findsOneWidget);
    expect(find.text('Таймлайн'), findsOneWidget);
    await tester.tap(find.text('Таймлайн'));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineScreen), findsOneWidget);
    await tester.tap(find.text('Мои задачи'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(store.tasks.first.title).first);
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsOneWidget);
    expect(find.text('Мои задачи'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть задачу'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Embedded board archive and delete preserve shell navigation', (
    tester,
  ) async {
    viewport(tester, const Size(1440, 900));
    final store = await demo();
    addTearDown(store.dispose);
    final project = await store.createProject(
      name: 'Проект для архива',
      key: 'ARC',
    );
    final task = await store.createTask(
      projectId: project.id,
      title: 'Сохранённая задача',
    );
    await tester.pumpWidget(TaskoApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text(project.name).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Действия проекта'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('В архив'));
    await tester.pumpAndSettle();
    expect(
      store.projects.firstWhere((p) => p.id == project.id).archived,
      isTrue,
    );
    expect(store.tasks.any((t) => t.id == task.id), isTrue);
    await tester.tap(find.byTooltip('Действия проекта'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Восстановить проект'));
    await tester.pumpAndSettle();
    expect(
      store.projects.firstWhere((p) => p.id == project.id).archived,
      isFalse,
    );
    await tester.tap(find.byTooltip('Действия проекта'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить проект'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(store.projects.any((p) => p.id == project.id), isFalse);
    expect(find.byType(TaskoShell), findsOneWidget);
    expect(find.text('Мои задачи'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Session end clears open profile routes', (tester) async {
    viewport(tester, const Size(390, 844));
    final store = await demo();
    addTearDown(store.dispose);
    await tester.pumpWidget(TaskoApp(store: store));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NavigationBar));
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ProfileScreen(store: store)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    await store.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inbox read all and empty mention tabs show actual state', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final store = await demo();
    addTearDown(store.dispose);
    final today = DateTime.now();
    store.tasks = [
      TaskoTask(
        id: 'due',
        projectId: store.projects.first.id,
        title: 'Сегодняшняя задача',
        createdAt: today,
        dueDate: DateTime(today.year, today.month, today.day),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InboxScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сегодняшняя задача'), findsOneWidget);
    await tester.tap(find.text('Прочитать все'));
    await tester.pumpAndSettle();
    expect(store.readReminderIds.length, 1);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Прочитать все'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Упоминания 0'));
    await tester.pumpAndSettle();
    expect(find.text('Нет упоминаний'), findsOneWidget);
    expect(find.text('Сегодняшняя задача'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Timeline opens real task and tolerates large text', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final store = await demo();
    addTearDown(store.dispose);
    final now = DateTime.now();
    store.tasks = [
      TaskoTask(
        id: 'timed',
        projectId: store.projects.first.id,
        title: 'Задача на шкале',
        createdAt: now,
        dueDate: now.add(const Duration(days: 3)),
      ),
    ];
    await tester.pumpWidget(TaskoApp(store: store));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NavigationBar));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.5)),
          child: TimelineScreen(
            store: store,
            projectId: store.projects.first.id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Месяц'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Следующий период'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Сегодня'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Задача на шкале'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
