import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tasko/legacy/legacy_main.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/ui/secondary_screens.dart';
import 'package:tasko/legacy/ui/task_detail_screen.dart';

import '../../tool/legacy/local_showcase.dart' as showcase;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('iPhone checklist and drag status persisted in local Supabase', (
    tester,
  ) async {
    await showcase.main();
    await tester.pumpAndSettle();
    final store = tester.widget<TaskoShell>(find.byType(TaskoShell)).store;
    expect(store.isDemo, isFalse);
    final project = store.projects.firstWhere((p) => p.key == 'LK');
    final task = store.tasks.firstWhere(
      (t) =>
          t.projectId == project.id &&
          t.title == 'Перенести форму смены тарифа на новый компонент',
    );
    final original = task.status;
    final destination = original == TaskStatus.review
        ? TaskStatus.inProgress
        : TaskStatus.review;

    Future<void> nav(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> waitStatus(TaskStatus status) async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (store.tasks.firstWhere((t) => t.id == task.id).status == status) {
          break;
        }
      }
      expect(store.tasks.firstWhere((t) => t.id == task.id).status, status);
      await store.refresh();
      expect(store.tasks.firstWhere((t) => t.id == task.id).status, status);
      await tester.pumpAndSettle();
    }

    await nav('Проекты');
    await binding.takeScreenshot('structure-projects');
    await tester.tap(find.text(project.name));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('board-status-${original.name}')));
    await tester.pumpAndSettle();
    final card = find.byKey(ValueKey('board-drag-${task.id}')).hitTestable();
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.moveTo(
      tester.getCenter(
        find.byKey(ValueKey('board-status-${destination.name}')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('board-hover');
    final column = find.byKey(ValueKey('board-column-${destination.name}'));
    expect(column.hitTestable(), findsOneWidget);
    await gesture.moveTo(tester.getCenter(column));
    await tester.pump();
    await binding.takeScreenshot('board-drag');
    await gesture.up();
    await waitStatus(destination);
    await binding.takeScreenshot('board-dropped');
    await tester.tap(find.text('Отмена'));
    await waitStatus(original);
    await tester.tap(find.byKey(ValueKey('board-status-${original.name}')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('structure-board');
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await nav('Задачи');
    await binding.takeScreenshot('structure-tasks');
    await tester.ensureVisible(find.text(task.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(task.title));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsOneWidget);
    await binding.takeScreenshot('task-detail');
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await nav('Сводка');
    await tester.tap(find.byTooltip('Профиль'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    await binding.takeScreenshot('structure-profile');
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Настройки'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await binding.takeScreenshot('structure-settings');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Календарь и отчёты'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Календарь'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);
    await binding.takeScreenshot('structure-calendar');
    expect(tester.takeException(), isNull);
  });
}
