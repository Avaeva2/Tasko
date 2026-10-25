import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tasko/legacy/legacy_main.dart' as app;
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/ui/core_screens.dart';
import 'package:tasko/legacy/ui/secondary_screens.dart';
import 'package:tasko/legacy/ui/task_detail_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iPhone: real local Auth, project/task CRUD, status/report and reload',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.textContaining('Google Workspace'), findsNothing);
      expect(find.textContaining('Единый вход'), findsNothing);
      await tester.ensureVisible(find.text('Создать аккаунт'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Создать аккаунт'));
      await tester.pumpAndSettle();
      const email = String.fromEnvironment('TASKO_TEST_EMAIL');
      const password = String.fromEnvironment('TASKO_TEST_PASSWORD');
      expect(email, isNotEmpty);
      expect(password, isNotEmpty);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Мария Соколова');
      await tester.enterText(fields.at(1), email);
      await tester.enterText(fields.at(2), password);
      await tester.enterText(fields.at(3), password);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Зарегистрироваться'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Зарегистрироваться'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(find.byType(app.TaskoShell), findsOneWidget);
      final store = tester
          .widget<app.TaskoShell>(find.byType(app.TaskoShell))
          .store;
      expect(store.isDemo, isFalse);
      expect(store.profile.name, 'Мария Соколова');
      Future<void> nav(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
      }

      await nav('Проекты');
      await tester.tap(find.byTooltip('Создать проект'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Редизайн личного кабинета',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'LK');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Создать проект').last,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Создать проект').last,
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(store.projects.single.key, 'LK');
      await nav('Задачи');
      await tester.tap(find.byTooltip('Действия списка задач'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить задачу'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Перенести форму смены тарифа',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Создать задачу'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Создать задачу'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(store.tasks.single.title, 'Перенести форму смены тарифа');
      await tester.tap(find.text('Перенести форму смены тарифа'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Действия с задачей'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Редактировать'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<TaskStatus>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<TaskStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Готово').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Сохранить'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await store.refresh();
      await tester.pumpAndSettle();
      expect(store.tasks.single.status, TaskStatus.done);
      expect(store.tasks.single.completedAt, isNotNull);
      expect(find.byType(TaskDetailScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await nav('Сводка');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Календарь и отчёты'));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('report-navigation');
      await tester.tap(find.text('Отчёты'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportsScreen), findsOneWidget);
      await binding.takeScreenshot('reports');
      expect(find.text('Завершено за выбранный период'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final originalId = store.projects.single.id;
      await store.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), email);
      await tester.enterText(find.byType(TextFormField).at(1), password);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(find.byType(app.TaskoShell), findsOneWidget);
      expect(store.projects.single.id, originalId);
      expect(store.tasks.single.status, TaskStatus.done);
      await store.saveProfile('Мария Соколова', 'Продуктовый дизайнер');
      final p = store.projects.single;
      for (final item in [
        ('Согласовать тексты ошибок оплаты', TaskStatus.review, 1),
        ('Адаптив таблицы платежей для экранов 360 dp', TaskStatus.todo, 7),
        ('Пустые состояния раздела «Документы»', TaskStatus.todo, 9),
        ('Восстановление доступа по SMS', TaskStatus.blocked, -1),
        ('Тесты оплаты картой «Мир»', TaskStatus.inProgress, 3),
      ]) {
        await store.createTask(
          projectId: p.id,
          title: item.$1,
          status: item.$2,
          dueDate: DateTime.now().add(Duration(days: item.$3)),
        );
      }
      final crm = await store.createProject(
        name: 'Миграция на новую CRM',
        key: 'CRM',
        dueDate: DateTime.now().add(const Duration(days: 39)),
      );
      await store.createTask(
        projectId: crm.id,
        title: 'Сопоставление полей сделок',
        status: TaskStatus.inProgress,
        dueDate: DateTime.now(),
      );
      await store.createProject(
        name: 'Мобильное приложение 2.0',
        key: 'APP',
        dueDate: DateTime.now().add(const Duration(days: 72)),
      );
      await store.refresh();
      await nav('Сводка');
      await tester.pumpAndSettle();
      await binding.takeScreenshot('dashboard');
      await nav('Проекты');
      await tester.tap(find.text('Редизайн личного кабинета'));
      await tester.pumpAndSettle();
      expect(find.byType(BoardScreen), findsOneWidget);
      await binding.takeScreenshot('board');
      await store.setTheme('dark');
      await tester.pumpAndSettle();
      await binding.takeScreenshot('board-dark');
      await store.setTheme('light');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
