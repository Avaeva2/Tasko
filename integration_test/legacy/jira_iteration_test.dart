import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tasko/legacy/data/task_query.dart';
import 'package:tasko/legacy/legacy_main.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/ui/task_detail_screen.dart';
import 'package:tasko/legacy/ui/task_routes.dart';

import '../../tool/legacy/local_showcase.dart' as showcase;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('iPhone ranking, copying, checklist and views on local Supabase', (
    tester,
  ) async {
    await showcase.main();
    await tester.pumpAndSettle();
    final store = tester.widget<TaskoShell>(find.byType(TaskoShell)).store;
    expect(store.isDemo, isFalse);
    final previousTheme = store.theme;
    final project = await store.createProject(
      name: 'Проверка рабочего процесса',
      key:
          'J${DateTime.now().millisecondsSinceEpoch.toRadixString(36).substring(2).toUpperCase()}',
    );
    try {
      final tasks = <TaskoTask>[];
      for (final title in [
        'Уточнить требования',
        'Исправить оплату',
        'Проверить релиз',
      ]) {
        tasks.add(
          await store.createTask(
            projectId: project.id,
            title: title,
            status: TaskStatus.inProgress,
            issueType: title == 'Исправить оплату'
                ? TaskIssueType.bug
                : TaskIssueType.task,
            description: 'Сценарий проверки возврата с оплаты',
            dueDate: DateTime.now().add(const Duration(days: 2)),
          ),
        );
      }
      expect(tasks.map((t) => t.issueNumber), [1, 2, 3]);
      final source = tasks[1];
      await store.setTaskLabels(source.id, ['Web']);
      await store.addSubtask(source.id, 'Проверить возврат');
      final step = store.subtasks.singleWhere((s) => s.taskId == source.id);
      await store.setSubtaskDone(step.id, true);
      await store.addComment(source.id, 'Комментарий исходной задачи');
      await tester.pumpAndSettle();

      Future<void> nav(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> waitFor(bool Function() predicate) async {
        for (var i = 0; i < 100 && !predicate(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(predicate(), isTrue);
        await tester.pumpAndSettle();
      }

      Future<void> visible(Finder target) async {
        if (target.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            target,
            260,
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

      List<String> order() {
        final values =
            store.tasks
                .where(
                  (t) =>
                      t.projectId == project.id &&
                      t.status == TaskStatus.inProgress,
                )
                .toList()
              ..sort((a, b) => a.position.compareTo(b.position));
        return values.map((t) => t.id).toList();
      }

      await nav('Проекты');
      await tester.tap(find.text(project.name));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('board-status-inProgress')));
      await tester.pumpAndSettle();
      final last = find
          .byKey(ValueKey('board-drag-${tasks.last.id}'))
          .hitTestable();
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(last));
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.moveTo(
        tester.getCenter(
          find.byKey(ValueKey('board-before-${tasks.first.id}')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await waitFor(() => order().first == tasks.last.id);
      await store.refresh();
      expect(order(), [tasks.last.id, tasks.first.id, source.id]);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('jira-board-order');
      await tester.tap(find.text('Отмена'));
      await waitFor(() => order().first == tasks.first.id);
      await store.refresh();
      expect(order(), tasks.map((t) => t.id).toList());

      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await nav('Задачи');
      showTaskDetails(
        tester.element(find.byType(TaskoShell)),
        store,
        task: source,
      );
      await tester.pumpAndSettle();
      await visible(find.byTooltip('Редактировать подзадачу'));
      await tester.tap(find.byTooltip('Редактировать подзадачу'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'Проверить возврат после оплаты',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await waitFor(
        () =>
            store.subtasks.singleWhere((s) => s.id == step.id).title ==
            'Проверить возврат после оплаты',
      );
      expect(store.subtasks.singleWhere((s) => s.id == step.id).done, isTrue);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 700),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Действия с задачей'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Создать копию'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-copy-title')),
        'Проверить следующий релиз',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Создать копию'));
      await waitFor(
        () => store.tasks.any(
          (t) =>
              t.projectId == project.id &&
              t.title == 'Проверить следующий релиз',
        ),
      );
      final copy = store.tasks.singleWhere(
        (t) =>
            t.projectId == project.id && t.title == 'Проверить следующий релиз',
      );
      await store.refresh();
      await store.loadTaskDetails(copy.id);
      expect(copy.issueNumber, 4);
      expect(copy.issueType, TaskIssueType.bug);
      expect(copy.status, TaskStatus.todo);
      expect(copy.dueDate, isNull);
      expect(
        store.subtasks.singleWhere((s) => s.taskId == copy.id).done,
        isFalse,
      );
      expect(store.comments.where((c) => c.taskId == copy.id), isEmpty);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TaskDetailScreen>(find.byType(TaskDetailScreen)).taskId,
        copy.id,
      );
      await store.setTheme('light');
      await tester.pumpAndSettle();
      await binding.takeScreenshot('jira-task-detail');
      await store.setTheme('dark');
      await tester.pumpAndSettle();
      await binding.takeScreenshot('jira-task-detail-dark');
      await store.setTheme('light');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      // Copy is a new route; Back first returns to the source task.
      expect(
        tester.widget<TaskDetailScreen>(find.byType(TaskDetailScreen)).taskId,
        source.id,
      );
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Поиск задач'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), taskKey(source, project));
      await tester.pumpAndSettle();
      expect(find.text(source.title), findsOneWidget);
      expect(find.text(tasks.first.title), findsNothing);
      await tester.tap(find.byTooltip('Действия списка задач'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить представление'));
      await tester.pumpAndSettle();
      final viewName = 'Проверка ${project.key}';
      await tester.enterText(find.byType(TextFormField), viewName);
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await waitFor(() => find.text(viewName).evaluate().isNotEmpty);
      await binding.takeScreenshot('jira-saved-view');
      // Remove only this run's saved view, never the user's existing views.
      await tester.tap(find.byTooltip('Действия списка задач'));
      await tester.pumpAndSettle();
      final viewsMenu = find.textContaining('Представления ·');
      await tester.tap(viewsMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Удалить представление $viewName'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await store.setTheme(previousTheme);
      await store.deleteProject(project.id);
    }
  });
}
