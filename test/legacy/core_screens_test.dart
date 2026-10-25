import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/theme.dart';
import 'package:tasko/legacy/ui/core_screens.dart';

Widget harness(Widget child, {double textScale = 1}) => MaterialApp(
  locale: const Locale('ru'),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('ru')],
  theme: taskoTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: child,
);

Future<TaskoStore> emptyStore() async {
  final store = TaskoStore(persistDemo: false);
  await store.enterDemo();
  store.projects = [];
  store.tasks = [];
  return store;
}

void compactSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('Editor save stays above iPhone safe area and keyboard', (
    tester,
  ) async {
    compactSize(tester);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);
    final store = await emptyStore();
    addTearDown(store.dispose);
    final project = await store.createProject(name: 'Проект', key: 'PR');
    final task = await store.createTask(
      projectId: project.id,
      title: 'Пустые состояния раздела «Документы»',
    );
    store.tasks = [
      task.copyWith(labels: ['Учёба']),
    ];
    for (final editTask in [true, false]) {
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => editTask
                    ? showTaskEditor(context, store, task: store.tasks.single)
                    : showProjectEditor(context, store, project: project),
                child: const Text('Открыть редактор'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть редактор'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Сохранить');
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(844 - 34));
      await tester.enterText(
        find.byType(TextFormField).first,
        editTask ? 'Исправленная задача' : 'Исправленный проект',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      tester.view.padding = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(844 - 320 - 16));
      expect(tester.takeException(), isNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Сохранить'), findsNothing);
      expect(
        editTask ? store.tasks.single.title : store.projects.single.name,
        editTask ? 'Исправленная задача' : 'Исправленный проект',
      );
      expect(store.tasks.single.labels, ['Учёба']);
      tester.view.resetViewInsets();
      tester.view.padding = const FakeViewPadding(bottom: 34);
    }
  });

  testWidgets('Project form validates and creates a real project', (
    tester,
  ) async {
    compactSize(tester);
    final store = await emptyStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(harness(ProjectsScreen(store: store)));
    await tester.tap(find.text('Создать проект'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Создать проект').last,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать проект').last);
    await tester.pumpAndSettle();
    expect(find.text('Введите название проекта'), findsOneWidget);
    expect(find.text('От 2 до 10 латинских букв и цифр'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Учебный проект');
    await tester.enterText(find.byType(TextFormField).at(1), 'STUDY');
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Создать проект').last,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать проект').last);
    await tester.pumpAndSettle();
    expect(store.projects.single.name, 'Учебный проект');
    expect(store.projects.single.key, 'STUDY');
    expect(find.text('Учебный проект'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Task form creates, edits and completes a task', (tester) async {
    compactSize(tester);
    final store = await emptyStore();
    addTearDown(store.dispose);
    final project = await store.createProject(name: 'Проект', key: 'PR');
    await tester.pumpWidget(harness(TasksScreen(store: store)));
    await tester.tap(find.text('Добавить задачу'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Подготовить презентацию',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Создать задачу'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать задачу'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.title, 'Подготовить презентацию');
    expect(store.tasks.single.projectId, project.id);
    await tester.tap(find.byKey(const ValueKey('task-group-todo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подготовить презентацию'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Действия с задачей'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Редактировать'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Готовая презентация',
    );
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<TaskStatus>),
    );
    await tester.tap(find.byType(DropdownButtonFormField<TaskStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.title, 'Готовая презентация');
    expect(store.tasks.single.status, TaskStatus.done);
    expect(store.tasks.single.completedAt, isNotNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.status, TaskStatus.todo);
    expect(store.tasks.single.completedAt, isNull);
    expect(store.tasks.single.title, 'Готовая презентация');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Project row opens board and priority filter narrows tasks', (
    tester,
  ) async {
    compactSize(tester);
    final store = await emptyStore();
    addTearDown(store.dispose);
    final project = await store.createProject(name: 'Доска проекта', key: 'BD');
    await store.createTask(projectId: project.id, title: 'Обычная задача');
    await store.createTask(
      projectId: project.id,
      title: 'Важная задача',
      priority: TaskPriority.high,
    );
    await tester.pumpWidget(harness(ProjectsScreen(store: store)));
    await tester.tap(find.text('Доска проекта'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardScreen), findsOneWidget);
    expect(find.text('Обычная задача'), findsOneWidget);
    expect(find.text('Важная задача'), findsOneWidget);
    await tester.tap(find.byTooltip('Фильтр по приоритету'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Высокий'));
    await tester.pumpAndSettle();
    expect(find.text('Обычная задача'), findsNothing);
    expect(find.text('Важная задача'), findsOneWidget);
    final cancelled = await tester.startGesture(
      tester.getCenter(find.text('Важная задача')),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await cancelled.moveTo(tester.getCenter(find.text('В работе')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('board-column-inProgress')).hitTestable(),
      findsOneWidget,
    );
    // Hover changes the visible column, but data changes only on a valid drop.
    expect(store.tasks.every((task) => task.status == TaskStatus.todo), isTrue);
    await cancelled.moveTo(const Offset(195, 24));
    await cancelled.up();
    await tester.pumpAndSettle();
    expect(store.tasks.every((task) => task.status == TaskStatus.todo), isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('board-status-todo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-status-todo')));
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(
      tester.getCenter(find.text('Важная задача')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await drag.moveTo(tester.getCenter(find.text('В работе')));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(
      store.tasks.singleWhere((task) => task.title == 'Важная задача').status,
      TaskStatus.inProgress,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compact screens and task sheet support 150 percent text', (
    tester,
  ) async {
    compactSize(tester);
    final store = await emptyStore();
    addTearDown(store.dispose);
    final project = await store.createProject(
      name: 'Учебный проект',
      key: 'ED',
    );
    await store.createTask(
      projectId: project.id,
      title: 'Большой текст интерфейса',
      dueDate: DateTime.now(),
    );
    for (final screen in [
      DashboardScreen(
        store: store,
        onProjects: () {},
        onCalendar: () {},
        onReports: () {},
      ),
      ProjectsScreen(store: store),
      TasksScreen(store: store),
      BoardScreen(store: store, projectId: project.id),
    ]) {
      await tester.pumpWidget(harness(screen, textScale: 1.5));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '${screen.runtimeType} should not overflow',
      );
    }
    await tester.tap(find.byTooltip('Добавить задачу'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Создать задачу'),
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'The task sheet should scroll at large text sizes',
    );
  });
  testWidgets(
    'Dashboard expanded follows two column sections with real attention',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await emptyStore();
      addTearDown(store.dispose);
      final project = await store.createProject(name: 'Дизайн', key: 'DS');
      await store.createTask(
        projectId: project.id,
        title: 'Проверить форму',
        dueDate: DateTime.now(),
      );
      await store.createTask(
        projectId: project.id,
        title: 'Ожидаем доступ',
        status: TaskStatus.blocked,
        dueDate: DateTime.now().subtract(const Duration(days: 1)),
      );
      await tester.pumpWidget(
        harness(
          DashboardScreen(
            store: store,
            onProjects: () {},
            onCalendar: () {},
            onReports: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Требует внимания'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Ближайшие дедлайны')).dx,
        greaterThan(
          tester.getTopLeft(find.text('Мои задачи на сегодня')).dx + 500,
        ),
      );
      expect(find.text('Ожидаем доступ'), findsNWidgets(3));
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Создать задачу'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Tasks supports real deadline filter, project grouping and collapse',
    (tester) async {
      compactSize(tester);
      final store = await emptyStore();
      addTearDown(store.dispose);
      final project = await store.createProject(
        name: 'Группировка проекта',
        key: 'GP',
      );
      await store.createTask(
        projectId: project.id,
        title: 'Сегодняшняя задача',
        dueDate: DateTime.now(),
      );
      await store.createTask(projectId: project.id, title: 'Без дедлайна');
      String? selected;
      await tester.pumpWidget(
        harness(
          TasksScreen(store: store, onTaskSelected: (id) => selected = id),
        ),
      );
      await tester.ensureVisible(find.text('Срок'));
      await tester.tap(find.text('Срок'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сегодня'));
      await tester.pumpAndSettle();
      expect(find.text('Сегодняшняя задача'), findsOneWidget);
      expect(find.text('Без дедлайна'), findsNothing);
      await tester.tap(find.text('По статусу'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('По проекту'));
      await tester.pumpAndSettle();
      expect(find.text('Группировка проекта'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('task-group-${project.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Сегодняшняя задача'), findsNothing);
      await tester.tap(find.byKey(ValueKey('task-group-${project.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сегодняшняя задача'));
      expect(selected, store.tasks.first.id);
      await tester.tap(find.bySemanticsLabel('Завершить: Сегодняшняя задача'));
      await tester.pumpAndSettle();
      expect(store.tasks.first.status, TaskStatus.done);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Board compact begins with five status tabs, expanded exposes three views',
    (tester) async {
      compactSize(tester);
      final store = await emptyStore();
      addTearDown(store.dispose);
      final project = await store.createProject(
        name: 'Структура доски',
        key: 'BR',
      );
      await store.createTask(projectId: project.id, title: 'Колонка задачи');
      await tester.pumpWidget(
        harness(BoardScreen(store: store, projectId: project.id)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Tab), findsNWidgets(5));
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      final toolbarBottom = tester.getRect(find.byType(AppBar)).bottom;
      expect(
        tester.getRect(find.byType(TabBar)).top,
        closeTo(toolbarBottom, 1),
      );
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      expect(find.byType(Tab), findsNWidgets(3));
      expect(find.text('Таймлайн'), findsOneWidget);
      expect(find.text('Проекты'), findsOneWidget);
      expect(find.text('Колонка задачи'), findsOneWidget);
      await tester.tap(find.text('Список'));
      await tester.pumpAndSettle();
      expect(find.text('Колонка задачи'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Tasks compact matches source05 toolbar grouping and single line rows',
    (tester) async {
      compactSize(tester);
      final store = await emptyStore();
      addTearDown(store.dispose);
      final project = await store.createProject(
        name: 'Личные задачи',
        key: 'UI',
      );
      final longTask = await store.createTask(
        projectId: project.id,
        title: 'Перенести форму смены тарифа на новый компонент и проверить длинный заголовок',
        status: TaskStatus.inProgress,
        priority: TaskPriority.high,
        dueDate: DateTime.now(),
      );
      await store.createTask(
        projectId: project.id,
        title: 'Проверка ревью',
        status: TaskStatus.review,
      );
      await store.createTask(projectId: project.id, title: 'Задача в очереди');
      await store.createTask(
        projectId: project.id,
        title: 'Завершённая задача',
        status: TaskStatus.done,
      );
      await tester.pumpWidget(harness(TasksScreen(store: store)));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Поиск задач'), findsOneWidget);
      expect(find.byTooltip('Действия списка задач'), findsOneWidget);
      expect(find.byTooltip('Добавить задачу'), findsNothing);
      expect(find.text('Задача в очереди'), findsNothing);
      expect(find.text('Завершённая задача'), findsNothing);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('task-group-in_progress')))
            .dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('task-group-review'))).dy,
        ),
      );
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('task-title-${longTask.id}')))
            .maxLines,
        1,
      );
      final taskTitle = tester.getRect(
        find.byKey(ValueKey('task-title-${longTask.id}')),
      );
      expect(taskTitle.left, closeTo(48, 1));
      expect(find.text('Высокий'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('task-group-todo')));
      await tester.pumpAndSettle();
      expect(find.text('Задача в очереди'), findsOneWidget);
      await tester.tap(find.byTooltip('Действия списка задач'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Показать завершённые'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-group-done')), findsOneWidget);
      await tester.pumpWidget(
        harness(TasksScreen(store: store), textScale: 1.5),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('task-title-${longTask.id}')))
            .maxLines,
        3,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
