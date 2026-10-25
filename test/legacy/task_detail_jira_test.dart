import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/theme.dart';
import 'package:tasko/legacy/ui/core_screens.dart';
import 'package:tasko/legacy/ui/task_detail_screen.dart';

Future<(TaskoStore, TaskoTask)> _source({
  TaskoStore? delayed,
  String? title,
}) async {
  final store = delayed ?? TaskoStore(persistDemo: false);
  await store.initialize();
  await store.enterDemo();
  final project = await store.createProject(
    name: 'Рабочие сценарии',
    key: 'JIRA',
  );
  final task = await store.createTask(
    projectId: project.id,
    title:
        title ??
        'Исправить потерю выбранного тарифа при возврате на страницу оплаты',
    description: 'Выбранный тариф должен сохраняться. Воспроизвести возврат, исправить состояние и проверить сценарий.',
    status: TaskStatus.done,
    priority: TaskPriority.high,
    issueType: TaskIssueType.bug,
    dueDate: DateTime.now().add(const Duration(days: 3)),
  );
  await store.setTaskLabels(task.id, ['Web', 'Оплата']);
  await store.addSubtask(task.id, 'Исправить опечатку в сообщении');
  final first = store.subtasks.singleWhere((step) => step.taskId == task.id);
  await store.setSubtaskDone(first.id, true);
  await store.addSubtask(task.id, 'Проверить сохранение тарифа');
  await store.addComment(task.id, 'Исходная проверка завершена');
  return (store, store.tasks.firstWhere((value) => value.id == task.id));
}

Future<void> _pump(
  WidgetTester tester,
  TaskoStore store,
  String taskId, {
  double width = 390,
  double scale = 1,
  Brightness brightness = Brightness.light,
  ValueChanged<String>? onCopy,
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
        taskId: taskId,
        embedded: onCopy != null,
        onTaskCopied: onCopy,
        onEdit: (context, task) => showTaskEditor(context, store, task: task),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _visible(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('task-detail-content')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _copyDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Действия с задачей'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Создать копию'));
  await tester.pumpAndSettle();
}

class _DelayedCopyStore extends TaskoStore {
  _DelayedCopyStore() : super(persistDemo: false);
  final gate = Completer<void>();
  String? target;
  @override
  Future<TaskoTask> duplicateTask(
    String id, {
    required String title,
    bool includeSubtasks = true,
    bool copyDueDate = false,
  }) async {
    target = id;
    await gate.future;
    return super.duplicateTask(
      id,
      title: title,
      includeSubtasks: includeSubtasks,
      copyDueDate: copyDueDate,
    );
  }
}

class _DelayedRenameStore extends TaskoStore {
  _DelayedRenameStore() : super(persistDemo: false);
  final gate = Completer<void>();
  String? target;
  @override
  Future<void> updateSubtask(String id, String title) async {
    target = id;
    await gate.future;
    await super.updateSubtask(id, title);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Копия независима, открывается и сбрасывает завершённость без истории источника',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (store, source) = await _source();
      addTearDown(store.dispose);
      final before = store.tasks.length;
      final originalHistory = store.activities
          .where((activity) => activity.taskId == source.id)
          .map((activity) => activity.id)
          .toSet();
      await _pump(tester, store, source.id);
      await _copyDialog(tester);
      await tester.enterText(
        find.byKey(const ValueKey('task-copy-title')),
        'Проверить следующий релиз',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Создать копию'));
      await tester.pumpAndSettle();
      expect(store.tasks, hasLength(before + 1));
      final copy = store.tasks.singleWhere(
        (task) => task.title == 'Проверить следующий релиз',
      );
      expect(copy.id, isNot(source.id));
      expect(copy.issueNumber, isNot(source.issueNumber));
      expect(copy.issueType, TaskIssueType.bug);
      expect(copy.status, TaskStatus.todo);
      expect(copy.completedAt, isNull);
      expect(copy.dueDate, isNull);
      expect(copy.labels, source.labels);
      final steps = store.subtasks
          .where((step) => step.taskId == copy.id)
          .toList();
      expect(steps, hasLength(2));
      expect(steps.every((step) => !step.done), isTrue);
      expect(
        store.comments.where((comment) => comment.taskId == copy.id),
        isEmpty,
      );
      final copyHistory = store.activities
          .where((activity) => activity.taskId == copy.id)
          .toList();
      expect(copyHistory, isNotEmpty);
      expect(
        copyHistory.every((activity) => !originalHistory.contains(activity.id)),
        isTrue,
      );
      expect(
        copyHistory.any((activity) => activity.body == 'Добавлен комментарий'),
        isFalse,
      );
      expect(
        tester.widget<TaskDetailScreen>(find.byType(TaskDetailScreen)).taskId,
        copy.id,
      );
      expect(
        store.tasks.firstWhere((task) => task.id == source.id).status,
        TaskStatus.done,
      );
      expect(
        store.subtasks.firstWhere((step) => step.taskId == source.id).done,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Флаги копии сохраняют срок и исключают чеклист; пустое название не сохраняется',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (store, source) = await _source(
        title: List.filled(120, 'Я').join(),
      );
      addTearDown(store.dispose);
      final before = store.tasks.length;
      await _pump(tester, store, source.id);
      await _copyDialog(tester);
      final input = tester.widget<TextFormField>(
        find.byKey(const ValueKey('task-copy-title')),
      );
      expect(input.controller!.text.length, lessThanOrEqualTo(120));
      expect(input.controller!.text.endsWith(' — копия'), isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('task-copy-title')),
        '   ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Создать копию'));
      await tester.pumpAndSettle();
      expect(find.text('Введите название задачи'), findsOneWidget);
      expect(store.tasks, hasLength(before));
      await tester.enterText(
        find.byKey(const ValueKey('task-copy-title')),
        'Повторная проверка',
      );
      await tester.tap(
        find.widgetWithText(CheckboxListTile, 'Копировать подзадачи'),
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Сохранить срок'));
      await tester.tap(find.widgetWithText(FilledButton, 'Создать копию'));
      await tester.pumpAndSettle();
      final copy = store.tasks.singleWhere(
        (task) => task.title == 'Повторная проверка',
      );
      expect(copy.dueDate, source.dueDate);
      expect(store.subtasks.where((step) => step.taskId == copy.id), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Подзадача переименовывается без сброса done/id; скрытие сохраняет общий счётчик',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (store, source) = await _source();
      addTearDown(store.dispose);
      final original = store.subtasks.firstWhere(
        (step) => step.taskId == source.id,
      );
      await _pump(tester, store, source.id);
      await _visible(tester, find.text(original.title));
      await tester.tap(find.text(original.title));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), ' ');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Введите название подзадачи'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        'Исправить формулировку сообщения',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      final saved = store.subtasks.firstWhere((step) => step.id == original.id);
      expect(saved.title, 'Исправить формулировку сообщения');
      expect(saved.done, isTrue);
      expect(saved.createdAt, original.createdAt);
      await _visible(tester, find.byTooltip('Настройки подзадач'));
      await tester.tap(find.byTooltip('Настройки подзадач'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Скрыть выполненные'));
      await tester.pumpAndSettle();
      expect(find.text(saved.title), findsNothing);
      expect(find.text('1/2'), findsOneWidget);
      await _visible(tester, find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('Все подзадачи выполнены'), findsOneWidget);
      await tester.tap(find.text('Показать все'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Поздняя копия не перехватывает переключённую pane и доступна через действие открытия',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final delayed = _DelayedCopyStore();
      final (store, source) = await _source(delayed: delayed);
      addTearDown(store.dispose);
      final next = await store.createTask(
        projectId: source.projectId,
        title: 'Другая рабочая задача',
      );
      final opened = <String>[];
      await _pump(tester, store, source.id, onCopy: opened.add);
      final state = tester.state(find.byType(TaskDetailScreen));
      await _copyDialog(tester);
      await tester.enterText(
        find.byKey(const ValueKey('task-copy-title')),
        'Копия исходного сценария',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Создать копию'));
      await tester.pumpAndSettle();
      expect(delayed.target, source.id);
      await _pump(tester, store, next.id, onCopy: opened.add);
      expect(
        identical(tester.state(find.byType(TaskDetailScreen)), state),
        isTrue,
      );
      delayed.gate.complete();
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text(next.title), findsOneWidget);
      expect(find.text('Копия создана'), findsOneWidget);
      final copy = store.tasks.singleWhere(
        (task) => task.title == 'Копия исходного сценария',
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(opened, [copy.id]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Тип задачи задаётся при создании и сохраняется через общую форму редактирования',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (store, source) = await _source();
      addTearDown(store.dispose);
      await _pump(tester, store, source.id);
      await tester.tap(find.byTooltip('Изменить тип задачи'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('История').last);
      await tester.pumpAndSettle();
      expect(
        store.tasks.firstWhere((task) => task.id == source.id).issueType,
        TaskIssueType.story,
      );
      await tester.tap(find.byTooltip('Действия с задачей'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Редактировать'));
      await tester.pumpAndSettle();
      final type = find.byType(DropdownButtonFormField<TaskIssueType>);
      await _visible(tester, type);
      await tester.tap(type);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ошибка').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      final saved = store.tasks.firstWhere((task) => task.id == source.id);
      expect(saved.issueType, TaskIssueType.bug);
      expect(saved.issueNumber, source.issueNumber);
      expect(saved.labels, source.labels);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Новая задача получает выбранный тип из формы создания', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (store, source) = await _source();
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: taskoTheme(Brightness.light),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showTaskEditor(context, store, projectId: source.projectId),
              child: const Text('Новая задача'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Новая задача'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Ошибка сохранения настроек',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final type = find.byType(DropdownButtonFormField<TaskIssueType>);
    await tester.ensureVisible(type);
    await tester.pumpAndSettle();
    await tester.tap(type);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ошибка').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Создать задачу'));
    await tester.pumpAndSettle();
    final saved = store.tasks.singleWhere(
      (task) => task.title == 'Ошибка сохранения настроек',
    );
    expect(saved.issueType, TaskIssueType.bug);
    expect(saved.projectId, source.projectId);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Позднее переименование изменяет исходный шаг и сохраняет выбор новой pane',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final delayed = _DelayedRenameStore();
      final (store, source) = await _source(delayed: delayed);
      addTearDown(store.dispose);
      final step = store.subtasks.firstWhere(
        (step) => step.taskId == source.id,
      );
      final next = await store.createTask(
        projectId: source.projectId,
        title: 'Другая рабочая задача',
      );
      await _pump(tester, store, source.id, onCopy: (_) {});
      await _visible(tester, find.text(step.title));
      await tester.tap(find.text(step.title));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'Скорректированный исходный шаг',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      expect(delayed.target, step.id);
      await _pump(tester, store, next.id, onCopy: (_) {});
      delayed.gate.complete();
      await tester.pumpAndSettle();
      expect(
        store.subtasks.firstWhere((value) => value.id == step.id).title,
        'Скорректированный исходный шаг',
      );
      expect(
        store.subtasks.firstWhere((value) => value.id == step.id).done,
        isTrue,
      );
      expect(store.subtasks.where((value) => value.taskId == next.id), isEmpty);
      expect(find.text(next.title), findsOneWidget);
      expect(find.text('Скорректированный исходный шаг'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('Copy/rename: $width, $brightness, текст150%, клавиатура', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final (store, source) = await _source();
        addTearDown(store.dispose);
        await _pump(
          tester,
          store,
          source.id,
          width: width,
          brightness: brightness,
          scale: 1.5,
        );
        expect(tester.takeException(), isNull);
        await _copyDialog(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('task-copy-title')),
          'Проверка большого текста',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Отмена'));
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        final step = store.subtasks.firstWhere(
          (step) => step.taskId == source.id,
        );
        await _visible(tester, find.text(step.title));
        await tester.tap(find.text(step.title));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        expect(find.text('Редактировать подзадачу'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
