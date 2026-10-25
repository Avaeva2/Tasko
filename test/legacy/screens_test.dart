import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/legacy_main.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/theme.dart';
import 'package:tasko/legacy/ui/secondary_screens.dart';

Future<TaskoStore> _demo() async {
  final store = TaskoStore(persistDemo: false);
  await store.initialize();
  await store.enterDemo();
  return store;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: taskoTheme(brightness),
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

TaskoTask _task(
  String id,
  String title,
  DateTime due, {
  TaskStatus status = TaskStatus.todo,
  DateTime? completedAt,
}) => TaskoTask(
  id: id,
  projectId: 'project',
  title: title,
  dueDate: due,
  status: status,
  completedAt: completedAt,
  createdAt: DateTime(due.year, due.month, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final screens = <String, Widget Function(TaskoStore)>{
    'регистрация и вход': (store) => AuthScreen(store: store),
    'календарь': (store) => CalendarScreen(store: store),
    'отчёты': (store) => ReportsScreen(store: store),
    'профиль': (store) => ProfileScreen(store: store),
    'настройки': (store) => SettingsScreen(store: store),
    'команда': (store) => Scaffold(body: TeamScreen(store: store)),
    'входящие': (store) => Scaffold(body: InboxScreen(store: store)),
  };

  for (final brightness in Brightness.values) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key}: compact, $brightness, текст 150%', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await _demo();
        addTearDown(store.dispose);
        await _pumpScreen(
          tester,
          entry.value(store),
          brightness: brightness,
          scale: 1.5,
        );
        if (entry.key == 'регистрация и вход') {
          await tester.ensureVisible(find.text('Создать аккаунт'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Создать аккаунт'));
          await tester.pumpAndSettle();
          expect(find.text('Повторите пароль'), findsOneWidget);
        }
        // Paint both the initial viewport and the content below it: large text
        // must remain readable throughout each screen, not only at its top.
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isNotEmpty) {
          for (var viewport = 0; viewport < 12; viewport++) {
            final state = tester.state<ScrollableState>(scrollables.first);
            if (state.position.extentAfter <= 0) break;
            await tester.drag(scrollables.first, const Offset(0, -550));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Email-регистрация и демо доступны без сторонних кнопок входа', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = TaskoStore(persistDemo: false);
    addTearDown(store.dispose);
    await store.initialize();
    await _pumpScreen(tester, AuthScreen(store: store));
    expect(find.text('Рабочая почта'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.textContaining('Google Workspace'), findsNothing);
    expect(find.textContaining('Единый вход'), findsNothing);
    await tester.ensureVisible(find.text('Создать аккаунт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать аккаунт'));
    await tester.pumpAndSettle();
    expect(find.text('Ваше имя'), findsOneWidget);
    expect(find.text('Рабочая почта'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.text('Повторите пароль'), findsOneWidget);
    await tester.ensureVisible(find.text('Попробовать демо'));
    await tester.pumpAndSettle();
    expect(find.text('Попробовать демо'), findsOneWidget);
    expect(find.textContaining('Google Workspace'), findsNothing);
    expect(find.textContaining('Единый вход'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Календарь открывает задачи выбранного дня и следующего месяца', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _demo();
    addTearDown(store.dispose);
    final now = DateTime.now();
    store.projects = [
      const TaskoProject(id: 'project', name: 'Учебный проект', key: 'STUDY'),
    ];
    store.tasks = [
      _task('one', 'Подготовить прототип', DateTime(now.year, now.month, 15)),
      _task('two', 'Защитить проект', DateTime(now.year, now.month + 1, 15)),
    ];
    await _pumpScreen(tester, CalendarScreen(store: store));
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    expect(find.text('Подготовить прототип'), findsOneWidget);
    expect(find.text('Защитить проект'), findsNothing);
    await tester.tap(find.byTooltip('Следующий месяц'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    expect(find.text('Защитить проект'), findsOneWidget);
    expect(find.text('Подготовить прототип'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Отчёт фильтрует завершения по периоду, сохраняя текущий прогресс',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _demo();
      addTearDown(store.dispose);
      final now = DateTime.now();
      final current = DateTime(now.year, now.month, now.day);
      store.projects = [
        const TaskoProject(id: 'project', name: 'Учебный проект', key: 'STUDY'),
      ];
      store.tasks = [
        _task(
          'done-now',
          'Прототип',
          current,
          status: TaskStatus.done,
          completedAt: current,
        ),
        _task(
          'done-before',
          'Исследование',
          DateTime(now.year, now.month, 0),
          status: TaskStatus.done,
          completedAt: DateTime(now.year, now.month, 0),
        ),
        _task('open', 'Защита', current.add(const Duration(days: 1))),
      ];
      await _pumpScreen(tester, ReportsScreen(store: store));
      expect(find.text('2 из 3 задач завершено'), findsOneWidget);
      final completedRow = find
          .ancestor(
            of: find.text('Завершено за выбранный период'),
            matching: find.byType(Row),
          )
          .first;
      expect(
        find.descendant(of: completedRow, matching: find.text('1')),
        findsOneWidget,
      );
      await tester.tap(find.text('Этот месяц'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('За всё время').last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: completedRow, matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.text('2 из 3 задач завершено'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Профиль не сохраняет пустое имя и сохраняет исправленные данные',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _demo();
      addTearDown(store.dispose);
      final original = store.profile.name;
      await _pumpScreen(tester, ProfileScreen(store: store));
      await tester.enterText(find.byType(TextFormField).first, '   ');
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Введите имя'), findsOneWidget);
      expect(store.profile.name, original);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Полина Иванова',
      );
      await tester.enterText(find.byType(TextFormField).last, 'Студентка');
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(store.profile.name, 'Полина Иванова');
      expect(store.profile.role, 'Студентка');
      expect(find.text('Профиль сохранён'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Выбор темы и напоминаний сохраняется после повторного запуска store',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TaskoStore();
      addTearDown(store.dispose);
      await store.initialize();
      await store.enterDemo();
      await _pumpScreen(tester, SettingsScreen(store: store));
      await tester.tap(find.text('Тёмная'));
      await tester.pumpAndSettle();
      expect(store.theme, 'dark');
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(store.deadlineReminders, isFalse);
      final reopened = TaskoStore();
      addTearDown(reopened.dispose);
      await reopened.initialize();
      expect(reopened.theme, 'dark');
      expect(reopened.deadlineReminders, isFalse);
      await _pumpScreen(tester, Scaffold(body: InboxScreen(store: store)));
      expect(find.text('Напоминания отключены'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Демо запускается из входа и главная навигация открывает команду',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TaskoStore(persistDemo: false);
      addTearDown(store.dispose);
      await store.initialize();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(TaskoApp(store: store));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Попробовать демо'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Попробовать демо'));
      await tester.pumpAndSettle();
      expect(store.isDemo, isTrue);
      expect(store.isAuthenticated, isTrue);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Команда'));
      await tester.pumpAndSettle();
      expect(find.text('Участники'), findsOneWidget);
      expect(find.text(store.profile.name), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
