import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/theme.dart';
import 'package:tasko/legacy/ui/task_detail_screen.dart';
import 'package:tasko/legacy/ui/widgets.dart';

Future<(TaskoStore, TaskoTask)> _fixture({
  bool persist = false,
  TaskoStore? storeOverride,
}) async {
  final store = storeOverride ?? TaskoStore(persistDemo: persist);
  await store.initialize();
  await store.enterDemo();
  final project = await store.createProject(
    name: 'Курсовой проект',
    key: 'DETAIL',
  );
  final task = await store.createTask(
    projectId: project.id,
    title: 'Подготовить прототип мобильного приложения для защиты курсового проекта',
    description: 'Проверить сценарии регистрации, проектирования задач и отчёта. Прототип должен работать на небольшом экране.',
    priority: TaskPriority.high,
    dueDate: DateTime.now().add(const Duration(days: 2)),
  );
  return (store, task);
}

class _DelayedStore extends TaskoStore {
  _DelayedStore() : super(persistDemo: false);
  final deleteGate = Completer<void>();
  final commentGate = Completer<void>();
  String? deletedTarget;
  String? commentTarget;

  @override
  Future<void> deleteTask(String id) async {
    deletedTarget = id;
    await deleteGate.future;
    await super.deleteTask(id);
  }

  @override
  Future<void> addComment(String taskId, String body) async {
    commentTarget = taskId;
    await commentGate.future;
    await super.addComment(taskId, body);
  }
}

Future<void> _pump(
  WidgetTester tester,
  TaskoStore store,
  String id, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  bool embedded = false,
  VoidCallback? onClose,
  Future<void> Function(BuildContext, TaskoTask)? onEdit,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: taskoTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: TaskDetailScreen(
        store: store,
        taskId: id,
        onEdit: onEdit ?? (_, _) async {},
        embedded: embedded,
        onClose: onClose,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _visible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Screen 06: $brightness, текст 150%, клавиатура и полная прокрутка',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final (store, task) = await _fixture();
        addTearDown(store.dispose);
        await store.setTaskLabels(task.id, [
          'Мобильное приложение',
          'Курсовой проект',
        ]);
        await store.addSubtask(
          task.id,
          'Проверить масштаб текста на небольшом экране и не потерять кнопку сохранения',
        );
        await store.addComment(
          task.id,
          'Все проверки сохраняются, а не являются статичным текстом макета.',
        );
        await _pump(tester, store, task.id, brightness: brightness, scale: 1.5);
        expect(find.text(task.title), findsOneWidget);
        expect(find.text('Курсовой проект'), findsWidgets);
        expect(find.text('Исполнитель'), findsOneWidget);
        expect(find.text(store.profile.name), findsWidgets);
        expect(
          find.text(
            taskReference(
              task,
              store.projects.firstWhere((p) => p.id == task.projectId),
            ),
          ),
          findsOneWidget,
        );
        final content = find.byKey(const ValueKey('task-detail-content'));
        for (var i = 0; i < 8; i++) {
          await tester.drag(content, const Offset(0, -450));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(
          find.text(
            'Все проверки сохраняются, а не являются статичным текстом макета.',
          ),
          findsOneWidget,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('task-comment-input')),
          'Комментарий с клавиатурой',
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Отправить комментарий'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'ID копируется без подмены, редактирование получает настоящую задачу',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (store, task) = await _fixture();
      addTearDown(store.dispose);
      String? copied;
      TaskoTask? edited;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      await _pump(
        tester,
        store,
        task.id,
        onEdit: (_, value) async {
          edited = value;
        },
      );
      await tester.tap(find.byTooltip('Скопировать ID задачи'));
      await tester.pumpAndSettle();
      expect(copied, task.id);
      await tester.tap(find.byTooltip('Действия с задачей'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Редактировать'));
      await tester.pumpAndSettle();
      expect(edited?.id, task.id);
      expect(edited?.title, task.title);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Статус, приоритет и срок меняются без потери меток и деталей', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (store, task) = await _fixture();
    addTearDown(store.dispose);
    await store.setTaskLabels(task.id, ['Прототип']);
    await store.addSubtask(task.id, 'Проверить прототип');
    await _pump(tester, store, task.id);
    await tester.tap(find.byTooltip('Изменить статус'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово').last);
    await tester.pumpAndSettle();
    expect(
      store.tasks.firstWhere((value) => value.id == task.id).status,
      TaskStatus.done,
    );
    await tester.tap(find.byTooltip('Изменить приоритет'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Срочный'));
    await tester.pumpAndSettle();
    await _visible(tester, find.byTooltip('Убрать срок'));
    await tester.tap(find.byTooltip('Убрать срок'));
    await tester.pumpAndSettle();
    final saved = store.tasks.firstWhere((value) => value.id == task.id);
    expect(saved.priority, TaskPriority.urgent);
    expect(saved.dueDate, isNull);
    expect(saved.labels, ['Прототип']);
    expect(
      store.subtasks.where((value) => value.taskId == task.id),
      hasLength(1),
    );
    expect(
      store.activities.where((value) => value.taskId == task.id),
      isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Подзадача проверяет название, добавляется, завершается и удаляется',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (store, task) = await _fixture();
      addTearDown(store.dispose);
      await _pump(tester, store, task.id);
      await _visible(tester, find.text('Добавить подзадачу'));
      await tester.tap(find.text('Добавить подзадачу'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await tester.pumpAndSettle();
      expect(find.text('Введите название подзадачи'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Проверить канбан');
      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await tester.pumpAndSettle();
      final subtask = store.subtasks.singleWhere(
        (value) => value.taskId == task.id,
      );
      expect(subtask.title, 'Проверить канбан');
      await _visible(tester, find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(
        store.subtasks.singleWhere((value) => value.id == subtask.id).done,
        isTrue,
      );
      expect(find.text('1/1'), findsOneWidget);
      await tester.tap(find.byTooltip('Удалить подзадачу Проверить канбан'));
      await tester.pumpAndSettle();
      expect(store.subtasks.where((value) => value.taskId == task.id), isEmpty);
      expect(find.text('0/0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Метки и комментарий сохраняются; история отражает реальные изменения',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (store, task) = await _fixture(persist: true);
      addTearDown(store.dispose);
      await _pump(tester, store, task.id);
      await _visible(tester, find.byTooltip('Изменить метки'));
      await tester.tap(find.byTooltip('Изменить метки'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Учеба, Прототип');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      expect(store.tasks.firstWhere((value) => value.id == task.id).labels, [
        'Учеба',
        'Прототип',
      ]);
      expect(find.text('Учеба'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('task-comment-input')),
        'Прототип готов к проверке',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Отправить комментарий'));
      await tester.pumpAndSettle();
      expect(
        store.comments.singleWhere((value) => value.taskId == task.id).body,
        'Прототип готов к проверке',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('task-comment-input')))
            .controller!
            .text,
        isEmpty,
      );
      await _visible(tester, find.text('История'));
      await tester.tap(find.text('История'));
      await tester.pumpAndSettle();
      expect(
        store.activities.where((value) => value.taskId == task.id),
        isNotEmpty,
      );
      expect(find.text('Изменений пока нет.'), findsNothing);
      final restored = TaskoStore();
      addTearDown(restored.dispose);
      await restored.initialize();
      await restored.enterDemo();
      await restored.loadTaskDetails(task.id);
      expect(restored.tasks.firstWhere((value) => value.id == task.id).labels, [
        'Учеба',
        'Прототип',
      ]);
      expect(
        restored.comments.singleWhere((value) => value.taskId == task.id).body,
        'Прототип готов к проверке',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Удаление требует подтверждения и закрывает embedded панель', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (store, task) = await _fixture();
    addTearDown(store.dispose);
    var closed = 0;
    await _pump(
      tester,
      store,
      task.id,
      embedded: true,
      width: 420,
      scale: 1.5,
      onClose: () => closed++,
    );
    await tester.tap(find.byTooltip('Действия с задачей'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить задачу'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(store.tasks.any((value) => value.id == task.id), isTrue);
    expect(closed, 0);
    await tester.tap(find.byTooltip('Действия с задачей'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить задачу'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(store.tasks.any((value) => value.id == task.id), isFalse);
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Командная задача без назначения не присваивается текущему пользователю',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (store, task) = await _fixture();
      addTearDown(store.dispose);
      store.projects = store.projects
          .map(
            (project) => project.id == task.projectId
                ? TaskoProject(
                    id: project.id,
                    name: project.name,
                    key: project.key,
                    teamId: 'team',
                  )
                : project,
          )
          .toList();
      await _pump(
        tester,
        store,
        task.id,
        embedded: true,
        width: 420,
        scale: 1.5,
      );
      expect(find.text('Не назначен'), findsOneWidget);
      expect(find.text(store.profile.name), findsNothing);
      expect(find.text('Статус'), findsOneWidget);
      expect(find.text('Приоритет'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Позднее удаление предыдущей задачи не закрывает новую панель', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final delayed = _DelayedStore();
    final (store, task) = await _fixture(storeOverride: delayed);
    addTearDown(store.dispose);
    final next = await store.createTask(
      projectId: task.projectId,
      title: 'Следующая задача',
    );
    var closed = 0;
    await _pump(
      tester,
      store,
      task.id,
      embedded: true,
      width: 420,
      onClose: () => closed++,
    );
    final originalState = tester.state(find.byType(TaskDetailScreen));
    await tester.tap(find.byTooltip('Действия с задачей'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить задачу'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(delayed.deletedTarget, task.id);
    expect(store.tasks.any((value) => value.id == task.id), isTrue);
    await _pump(
      tester,
      store,
      next.id,
      embedded: true,
      width: 420,
      onClose: () => closed++,
    );
    expect(
      identical(tester.state(find.byType(TaskDetailScreen)), originalState),
      isTrue,
    );
    expect(find.text(next.title), findsOneWidget);
    delayed.deleteGate.complete();
    await tester.pumpAndSettle();
    expect(store.tasks.any((value) => value.id == task.id), isFalse);
    expect(store.tasks.any((value) => value.id == next.id), isTrue);
    expect(closed, 0);
    expect(find.text(next.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Поздний комментарий сохраняется к старой задаче и не меняет вкладку новой',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final delayed = _DelayedStore();
      final (store, task) = await _fixture(storeOverride: delayed);
      addTearDown(store.dispose);
      final next = await store.createTask(
        projectId: task.projectId,
        title: 'Следующая задача',
      );
      await store.addSubtask(next.id, 'Собрать вопросы для защиты');
      final nextActivity = store.activities.lastWhere(
        (activity) => activity.taskId == next.id,
      );
      await _pump(tester, store, task.id, embedded: true, width: 420);
      final originalState = tester.state(find.byType(TaskDetailScreen));
      await tester.enterText(
        find.byKey(const ValueKey('task-comment-input')),
        'Комментарий к первой задаче',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Отправить комментарий'));
      await tester.pumpAndSettle();
      expect(delayed.commentTarget, task.id);
      expect(store.comments.where((value) => value.taskId == task.id), isEmpty);
      await _pump(tester, store, next.id, embedded: true, width: 420);
      expect(
        identical(tester.state(find.byType(TaskDetailScreen)), originalState),
        isTrue,
      );
      await _visible(tester, find.text('История'));
      await tester.tap(find.text('История'));
      await tester.pumpAndSettle();
      expect(
        find.text('${nextActivity.actorName} · ${nextActivity.body}'),
        findsOneWidget,
      );
      delayed.commentGate.complete();
      await tester.pumpAndSettle();
      expect(
        store.comments.singleWhere((value) => value.taskId == task.id).body,
        'Комментарий к первой задаче',
      );
      expect(store.comments.where((value) => value.taskId == next.id), isEmpty);
      expect(
        find.text('${nextActivity.actorName} · ${nextActivity.body}'),
        findsOneWidget,
      );
      expect(
        find.text('Комментариев пока нет. Напишите первый.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
