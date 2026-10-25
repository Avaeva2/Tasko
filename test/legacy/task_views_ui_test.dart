import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasko/legacy/data/task_query.dart';
import 'package:tasko/legacy/data/task_views.dart';
import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/legacy_main.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/ui/core_screens.dart';

class _ScopedStore extends TaskoStore {
  _ScopedStore() : super(persistDemo: false);
  String activeScope = 'account-a';
  @override
  String? get preferenceScope => activeScope;
  void switchScope(String value) {
    activeScope = value;
    notifyListeners();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<TaskoStore> fixture({TaskoStore? scopedStore}) async {
    final store = scopedStore ?? TaskoStore(persistDemo: false);
    await store.enterDemo();
    store.tasks = [];
    store.projects = [];
    final project = await store.createProject(name: 'Учебный сайт', key: 'WEB');
    final task = await store.createTask(
      projectId: project.id,
      title: 'Починить оплату',
      description: 'Ёлочка и расчёт',
      issueType: TaskIssueType.bug,
      priority: TaskPriority.high,
      status: TaskStatus.inProgress,
    );
    await store.setTaskLabels(task.id, ['Web']);
    await store.createTask(
      projectId: project.id,
      title: 'Написать инструкцию',
      status: TaskStatus.inProgress,
    );
    addTearDown(store.dispose);
    return store;
  }

  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> menu(WidgetTester tester, String title) async {
    await tester.tap(find.byTooltip('Действия списка задач'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Search finds human keys and description, closing search clears hidden query',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await fixture();
      await tester.pumpWidget(TaskoApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Задачи'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Поиск задач'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' ЕЛОЧКА расчет ');
      await tester.pumpAndSettle();
      expect(find.text('Починить оплату'), findsOneWidget);
      expect(find.text('Написать инструкцию'), findsNothing);
      await tester.enterText(
        find.byType(TextField),
        taskKey(store.tasks.first, store.projects.first),
      );
      await tester.pumpAndSettle();
      expect(find.text('Починить оплату'), findsOneWidget);
      await tester.tap(find.byTooltip('Поиск задач'));
      await tester.pumpAndSettle();
      expect(find.text('Написать инструкцию'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Combined advanced filters and saved view apply/reset/reload/delete',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await fixture();
      await tester.pumpWidget(TaskoApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Задачи'),
        ),
      );
      await tester.pumpAndSettle();
      await menu(tester, 'Фильтры и сортировка');
      await tester.tap(find.byType(DropdownButtonFormField<int>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ошибка').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Web').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Применить'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Применить'));
      await tester.pumpAndSettle();
      expect(find.text('Починить оплату'), findsOneWidget);
      expect(find.text('Написать инструкцию'), findsNothing);
      await menu(tester, 'Сохранить представление');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Введите название'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Ошибки сайта');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Ошибки сайта'), findsOneWidget);
      await menu(tester, 'Сбросить фильтры');
      expect(find.text('Написать инструкцию'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(TaskoApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Задачи'),
        ),
      );
      await tester.pumpAndSettle();
      await menu(tester, 'Представления · 1');
      await tester.tap(find.text('Ошибки сайта'));
      await tester.pumpAndSettle();
      expect(find.text('Написать инструкцию'), findsNothing);
      expect(find.text('Починить оплату'), findsOneWidget);
      await menu(tester, 'Представления · 1');
      await tester.tap(find.byTooltip('Удалить представление Ошибки сайта'));
      await tester.pumpAndSettle();
      await menu(tester, 'Представления · 0');
      expect(find.textContaining('сохраните первое'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Advanced filters and saved-name keyboard fit 320px150% $brightness',
      (tester) async {
        viewport(tester, const Size(320, 740));
        addTearDown(tester.view.resetViewInsets);
        final store = await fixture();
        await store.setTheme(brightness == Brightness.dark ? 'dark' : 'light');
        await tester.pumpWidget(TaskoApp(store: store));
        await tester.pumpAndSettle();
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Задачи'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(TasksScreen)))
              .scale(10),
          15,
        );
        await menu(tester, 'Фильтры и сортировка');
        expect(
          MediaQuery.textScalerOf(
            tester.element(find.byKey(const ValueKey('task-filters-apply'))),
          ).scale(10),
          15,
        );
        await tester.drag(
          find.byKey(const ValueKey('task-filters-scroll')),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(FilledButton, 'Применить').hitTestable(),
          findsOneWidget,
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('task-filters-apply')))
              .bottom,
          lessThanOrEqualTo(740),
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('task-filters-apply')).hitTestable(),
          findsOneWidget,
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('task-filters-apply')))
              .bottom,
          lessThanOrEqualTo(480),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(FilledButton, 'Применить'));
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await menu(tester, 'Сохранить представление');
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField),
          'Длинное имя фильтра',
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(FilledButton, 'Сохранить').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Отмена'));
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'Same store scope change closes old chooser and clears private saved query',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final scoped = _ScopedStore();
      final store = await fixture(scopedStore: scoped);
      await const TaskViews('account-a')
          .save('Частное представление A', const TaskQuery(text: 'Починить'));
      await const TaskViews('account-b')
          .save('Представление B', const TaskQuery(text: 'Написать'));
      await tester.pumpWidget(TaskoApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Задачи'),
        ),
      );
      await tester.pumpAndSettle();
      await menu(tester, 'Представления · 1');
      await tester.tap(find.text('Частное представление A'));
      await tester.pumpAndSettle();
      expect(find.text('Написать инструкцию'), findsNothing);
      await menu(tester, 'Представления · 1');
      scoped.switchScope('account-b');
      await tester.pumpAndSettle();
      expect(find.text('Частное представление A'), findsNothing);
      expect(find.text('Представления'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Написать инструкцию'), findsOneWidget);
      expect(find.text('Починить оплату'), findsOneWidget);
      await menu(tester, 'Представления · 1');
      expect(find.text('Представление B'), findsOneWidget);
      expect(
        find.byTooltip('Удалить представление Частное представление A'),
        findsNothing,
      );
      await tester.tap(find.text('Представление B'));
      await tester.pumpAndSettle();
      expect(find.text('Написать инструкцию'), findsOneWidget);
      expect(find.text('Починить оплату'), findsNothing);
      expect(
        (await const TaskViews('account-a').load()).single.name,
        'Частное представление A',
      );
      expect(
        (await const TaskViews('account-b').load()).single.name,
        'Представление B',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Stale saved project gives reset action instead of creating task',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await fixture();
      await const TaskViews('demo')
          .save('Старый проект', const TaskQuery(projectId: 'deleted-project'));
      await tester.pumpWidget(TaskoApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Задачи'),
        ),
      );
      await tester.pumpAndSettle();
      await menu(tester, 'Представления · 1');
      await tester.tap(find.text('Старый проект'));
      await tester.pumpAndSettle();
      expect(find.text('Нет совпадений'), findsOneWidget);
      expect(find.textContaining('удалён или недоступен'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Сбросить фильтры'));
      await tester.pumpAndSettle();
      expect(find.text('Починить оплату'), findsOneWidget);
      expect(find.text('Написать инструкцию'), findsOneWidget);
      expect(find.text('Старый проект'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Deleting inactive saved view preserves active view label and grouping clears it',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final store = await fixture();
      await const TaskViews('demo')
          .save('Текущий вид', const TaskQuery(text: 'Починить'));
      await const TaskViews('demo').save('Другой вид', const TaskQuery());
      await tester.pumpWidget(TaskoApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Задачи'),
        ),
      );
      await tester.pumpAndSettle();
      await menu(tester, 'Представления · 2');
      await tester.tap(find.text('Текущий вид'));
      await tester.pumpAndSettle();
      await menu(tester, 'Представления · 2');
      await tester.tap(find.byTooltip('Удалить представление Другой вид'));
      await tester.pumpAndSettle();
      expect(find.text('Текущий вид'), findsOneWidget);
      await tester.tap(find.text('По статусу'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('По проекту'));
      await tester.pumpAndSettle();
      expect(find.text('Текущий вид'), findsNothing);
      expect(find.text('По проекту'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
