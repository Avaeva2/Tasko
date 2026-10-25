import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/theme.dart';
import 'package:tasko/legacy/ui/core_screens.dart';

Future<(TaskoStore, List<TaskoTask>)> _fixture() async {
  final store = TaskoStore();
  await store.initialize();
  await store.enterDemo();
  final project = await store.createProject(
    name: 'Очередь редактора',
    key: 'EDIT',
  );
  final items = <TaskoTask>[];
  for (final title in ['Первый', 'Редактируемый', 'Последний']) {
    items.add(await store.createTask(projectId: project.id, title: title));
  }
  // Storage order and card priority must not replace the manual board rank.
  await store.updateTask(items.last.copyWith(priority: TaskPriority.high));
  store.tasks = store.tasks.reversed.toList();
  return (store, items);
}

TaskoTask _task(TaskoStore store, String id) =>
    store.tasks.singleWhere((task) => task.id == id);

List<String> _column(TaskoStore store, String project, TaskStatus status) {
  final tasks =
      store.tasks
          .where((task) => task.projectId == project && task.status == status)
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));
  return tasks.map((task) => task.id).toList();
}

Future<void> _editStatus(
  WidgetTester tester,
  TaskoStore store,
  TaskoTask task,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: taskoTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTaskEditor(context, store, task: task),
            child: const Text('Редактировать'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Редактировать'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, 'Уточнённая задача');
  final status = find.byType(DropdownButtonFormField<TaskStatus>);
  await tester.ensureVisible(status);
  await tester.pumpAndSettle();
  await tester.tap(status);
  await tester.pumpAndSettle();
  await tester.tap(find.text(TaskStatus.inProgress.label).last);
  await tester.pumpAndSettle();
  final save = find.widgetWithText(FilledButton, 'Сохранить');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
  expect(_task(store, task.id).status, TaskStatus.inProgress);
  expect(find.text('Отмена'), findsOneWidget);
}

Future<void> _undo(WidgetTester tester) async {
  await tester.tap(find.text('Отмена'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Editor undo restores full manual order and survives demo reload',
    (tester) async {
      final (store, items) = await _fixture();
      addTearDown(store.dispose);
      await _editStatus(tester, store, items[1]);
      await store.refresh();
      await tester.pump();
      await _undo(tester);
      expect(
        _column(store, items.first.projectId, TaskStatus.todo),
        items.map((task) => task.id).toList(),
      );
      expect(_task(store, items[1].id).title, 'Уточнённая задача');
      await store.refresh();
      final restored = TaskoStore();
      addTearDown(restored.dispose);
      await restored.initialize();
      await restored.enterDemo();
      expect(
        _column(restored, items.first.projectId, TaskStatus.todo),
        items.map((task) => task.id).toList(),
      );
    },
  );

  for (final removed in [true, false]) {
    testWidgets(
      'Undo appends safely when the source anchor is ${removed ? 'deleted' : 'moved'}',
      (tester) async {
        final (store, items) = await _fixture();
        addTearDown(store.dispose);
        await _editStatus(tester, store, items[1]);
        if (removed) {
          await store.deleteTask(items.last.id);
        } else {
          await store.moveTask(items.last.id, TaskStatus.review);
        }
        await tester.pump();
        await _undo(tester);
        expect(_column(store, items.first.projectId, TaskStatus.todo), [
          items.first.id,
          items[1].id,
        ]);
        if (!removed) {
          expect(_task(store, items.last.id).status, TaskStatus.review);
        }
      },
    );
  }

  for (final newer in [
    'status',
    'edit',
    'status roundtrip',
    'delete',
    'session',
    'same-scope session reload',
  ]) {
    testWidgets('Old editor undo cannot overwrite a newer $newer', (
      tester,
    ) async {
      final (store, items) = await _fixture();
      addTearDown(store.dispose);
      await _editStatus(tester, store, items[1]);
      final id = items[1].id;
      switch (newer) {
        case 'status':
          await store.moveTask(id, TaskStatus.done);
        case 'edit':
          await store.updateTask(
            _task(store, id).copyWith(title: 'Позднее изменение'),
          );
        case 'status roundtrip':
          await store.moveTask(id, TaskStatus.review);
          await store.moveTask(id, TaskStatus.inProgress);
        case 'delete':
          await store.deleteTask(id);
        case 'session':
          await store.signOut();
          await store.enterDemo();
        case 'same-scope session reload':
          await store.enterDemo();
      }
      final expected = store.tasks.where((task) => task.id == id).firstOrNull;
      await tester.pump();
      await _undo(tester);
      expect(
        find.text(
          'Задача уже изменена или сессия завершена. Отмена недоступна.',
        ),
        findsOneWidget,
      );
      final actual = store.tasks.where((task) => task.id == id).firstOrNull;
      expect(actual?.status, expected?.status);
      expect(actual?.title, expected?.title);
      expect(actual?.position, expected?.position);
      expect(_column(store, items.first.projectId, TaskStatus.todo), [
        items.first.id,
        items.last.id,
      ]);
    });
  }
}
