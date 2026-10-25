import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tasko/legacy/legacy_main.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/ui/task_detail_screen.dart';
import 'package:tasko/legacy/ui/task_routes.dart';
import 'package:tasko/legacy/ui/secondary_screens.dart';
import 'package:tasko/legacy/ui/timeline_screen.dart';

import '../../tool/legacy/local_showcase.dart' as showcase;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native Tasko v2 structures and persisted task details', (
    tester,
  ) async {
    await showcase.main();
    await tester.pumpAndSettle();
    final store = tester.widget<TaskoShell>(find.byType(TaskoShell)).store;
    expect(store.isDemo, isFalse);
    final project = store.projects.firstWhere((p) => p.key == 'LK');
    final task = await store.createTask(
      projectId: project.id,
      title: 'Перенести форму смены тарифа на новый компонент',
      description: 'Форма смены тарифа собрана на старых полях и теряет выбор после возврата со страницы оплаты. Переносим её на новый компонент и сохраняем выбор в сессии.',
      dueDate: DateTime.now().add(const Duration(days: 2)),
      status: TaskStatus.inProgress,
      priority: TaskPriority.high,
    );
    bool verified = false;
    try {
      Future<void> visible(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }

      Future<void> nav(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
      }

      await store.setTaskLabels(task.id, ['Оплата', 'Web']);
      for (final title in [
        'Обновить поля формы',
        'Сохранить выбранный тариф',
        'Проверить возврат с оплаты',
      ]) {
        await store.addSubtask(task.id, title);
      }
      await tester.pumpAndSettle();
      await binding.takeScreenshot('structure-dashboard');
      await nav('Проекты');
      await binding.takeScreenshot('structure-projects');
      await tester.tap(find.text(project.name));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('structure-board');
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await nav('Задачи');
      await binding.takeScreenshot('structure-tasks');
      final context = tester.element(find.byType(TaskoShell));
      showTaskDetails(context, store, task: task);
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailScreen), findsOneWidget);
      await visible(find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(
        store.subtasks.firstWhere((s) => s.taskId == task.id).done,
        isTrue,
      );
      await visible(find.byType(Checkbox).last);
      await tester.enterText(
        find.byKey(const ValueKey('task-comment-input')),
        'Новый компонент готов к проверке на iPhone.',
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('task-detail-keyboard');
      await tester.tap(find.byTooltip('Отправить комментарий'));
      await tester.pumpAndSettle();
      await store.refresh();
      await store.loadTaskDetails(task.id);
      expect(
        store.comments.singleWhere((c) => c.taskId == task.id).body,
        'Новый компонент готов к проверке на iPhone.',
      );
      expect(store.tasks.firstWhere((t) => t.id == task.id).labels, [
        'Оплата',
        'Web',
      ]);
      expect(store.subtasks.where((s) => s.taskId == task.id), hasLength(3));
      expect(store.activities.where((a) => a.taskId == task.id), isNotEmpty);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 800),
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('task-detail');
      await store.setTheme('dark');
      await tester.pumpAndSettle();
      await binding.takeScreenshot('task-detail-dark');
      await store.setTheme('light');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await nav('Команда');
      await binding.takeScreenshot('structure-team');
      await nav('Входящие');
      await binding.takeScreenshot('structure-inbox');
      Navigator.of(tester.element(find.byType(TaskoShell))).push(
        MaterialPageRoute<void>(builder: (_) => SettingsScreen(store: store)),
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('structure-settings');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(TaskoShell))).push(
        MaterialPageRoute<void>(
          builder: (_) => TimelineScreen(store: store, projectId: project.id),
        ),
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('structure-timeline');
      expect(tester.takeException(), isNull);
      verified = true;
    } finally {
      // Preserve the successful local example for the user's simulator.
      // Only a fixture created by this failed run may be removed.
      if (!verified) await store.deleteTask(task.id);
    }
  });
}
