import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('move RPC for a concurrently changed project preserves old neighbors and deduplicates actual project', () {
    TaskoTask task(
      String id,
      String project, {
      TaskStatus status = TaskStatus.todo,
      int position = 1,
    }) => TaskoTask(
      id: id,
      projectId: project,
      title: id,
      status: status,
      position: position,
      createdAt: DateTime(2026, 10, 1),
    );
    final cached = [
      task('moved', 'A'),
      task('neighbor-A', 'A', position: 2),
      task('neighbor-B', 'B'),
      task('deleted-B', 'B', position: 2),
      task('neighbor-C', 'C'),
    ];
    // The store read source A. Another client moved it to B before the RPC,
    // whose authoritative complete project snapshot is consequently B.
    final actual = [
      task('neighbor-B', 'B', position: 1),
      task('moved', 'B', status: TaskStatus.review, position: 1),
    ];
    final merged = TaskoStore.mergeMovedTaskSnapshot(
      cached,
      actual,
      movedTaskId: 'moved',
    );
    expect(merged.map((t) => t.id).toSet(), {
      'neighbor-A',
      'neighbor-B',
      'neighbor-C',
      'moved',
    });
    expect(merged.where((t) => t.id == 'moved'), hasLength(1));
    expect(merged.where((t) => t.id == 'neighbor-B'), hasLength(1));
    expect(merged.singleWhere((t) => t.id == 'moved').projectId, 'B');
    expect(
      merged.singleWhere((t) => t.id == 'moved').status,
      TaskStatus.review,
    );
    expect(merged.singleWhere((t) => t.id == 'neighbor-A').projectId, 'A');
    expect(merged.singleWhere((t) => t.id == 'neighbor-C').projectId, 'C');
    expect(cached.first.projectId, 'A'); // Never mutate the caller's cache.
  });

  test('same-project RPC snapshot replaces stale rows and empty response cannot erase neighbors', () {
    TaskoTask task(String id) => TaskoTask(
      id: id,
      projectId: 'A',
      title: id,
      createdAt: DateTime(2026, 10, 1),
    );
    final current = [task('moved'), task('old-neighbor')];
    expect(
      TaskoStore.mergeMovedTaskSnapshot(current, [
        task('moved'),
        task('new-neighbor'),
      ], movedTaskId: 'moved').map((t) => t.id),
      ['moved', 'new-neighbor'],
    );
    expect(
      TaskoStore.mergeMovedTaskSnapshot(
        current,
        [],
        movedTaskId: 'moved',
      ).map((t) => t.id),
      ['old-neighbor'],
    );
  });

  Future<TaskoStore> demo({bool persist = false}) async {
    final store = TaskoStore(persistDemo: persist);
    addTearDown(store.dispose);
    await store.initialize();
    await store.enterDemo();
    return store;
  }

  List<String> order(TaskoStore store, String projectId, TaskStatus status) {
    final selected =
        store.tasks
            .where(
              (task) => task.projectId == projectId && task.status == status,
            )
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    return selected.map((task) => task.id).toList();
  }

  test(
    'legacy JSON receives numbers/rank without losing content or children',
    () async {
      final first = await demo(persist: true);
      await first.addSubtask('LK-142', 'Старый пользовательский пункт');
      await first.addComment('LK-142', 'Старый пользовательский комментарий');
      final prefs = await SharedPreferences.getInstance();
      final legacy =
          jsonDecode(prefs.getString('tasko.demo.v2')!) as Map<String, dynamic>;
      legacy.remove('issue_counters');
      for (final raw in legacy['tasks'] as List) {
        (raw as Map).remove('issue_type');
        raw.remove('issue_number');
        raw.remove('position');
      }
      await prefs.setString('tasko.demo.v2', jsonEncode(legacy));
      final restored = await demo(persist: true);
      final original = restored.tasks.firstWhere((t) => t.id == 'LK-142');
      expect(original.issueNumber, 142);
      expect(original.issueType, TaskIssueType.task);
      expect(original.position, greaterThan(0));
      expect(
        restored.comments.single.body,
        'Старый пользовательский комментарий',
      );
      expect(restored.subtasks.single.title, 'Старый пользовательский пункт');
      final next = await restored.createTask(
        projectId: 'LK',
        title: 'После миграции',
      );
      expect(next.issueNumber, 148);
    },
  );

  test(
    'number counter survives deleting last task and restarting empty project',
    () async {
      final first = await demo(persist: true);
      final project = await first.createProject(name: 'Нумерация', key: 'NUM');
      final one = await first.createTask(
        projectId: project.id,
        title: 'Первая',
        issueType: TaskIssueType.bug,
      );
      expect(one.issueNumber, 1);
      await first.deleteTask(one.id);
      final second = await demo(persist: true);
      final two = await second.createTask(
        projectId: project.id,
        title: 'Вторая',
        issueType: TaskIssueType.story,
      );
      expect(two.issueNumber, 2);
      expect(two.issueType, TaskIssueType.story);
      final copied = two.copyWith(title: 'Другое название');
      expect(copied.issueNumber, 2);
      expect(copied.issueType, TaskIssueType.story);
      expect(copied.position, two.position);
    },
  );

  test(
    'rank reorders with hidden siblings, cross-column append, noop and reload',
    () async {
      final store = await demo(persist: true);
      final project = await store.createProject(name: 'Порядок', key: 'RNK');
      final items = <TaskoTask>[];
      for (final title in ['A', 'Hidden', 'B', 'C']) {
        items.add(await store.createTask(projectId: project.id, title: title));
      }
      await store.moveTask(
        items[3].id,
        TaskStatus.todo,
        beforeTaskId: items[2].id,
      );
      expect(order(store, project.id, TaskStatus.todo), [
        items[0].id,
        items[1].id,
        items[3].id,
        items[2].id,
      ]);
      final snapshot = order(store, project.id, TaskStatus.todo);
      final historyCount = store.activities.length;
      await store.moveTask(
        items[3].id,
        TaskStatus.todo,
        beforeTaskId: items[3].id,
      );
      expect(order(store, project.id, TaskStatus.todo), snapshot);
      expect(store.activities, hasLength(historyCount));
      await store.moveTask(items[3].id, TaskStatus.done);
      expect(
        store.tasks.firstWhere((t) => t.id == items[3].id).completedAt,
        isNotNull,
      );
      await store.moveTask(
        items[3].id,
        TaskStatus.todo,
        beforeTaskId: items[2].id,
      );
      expect(order(store, project.id, TaskStatus.todo), snapshot);
      expect(
        store.tasks.firstWhere((t) => t.id == items[3].id).completedAt,
        isNull,
      );
      final restored = await demo(persist: true);
      expect(order(restored, project.id, TaskStatus.todo), snapshot);
    },
  );

  test('invalid rank target is atomic; project move gets new number and type stays', () async {
    final store = await demo();
    final one = await store.createProject(name: 'Первая область', key: 'ONE');
    final two = await store.createProject(name: 'Вторая область', key: 'TWO');
    final task = await store.createTask(
      projectId: one.id,
      title: 'Перенос',
      issueType: TaskIssueType.bug,
    );
    final target = await store.createTask(
      projectId: two.id,
      title: 'Чужая колонка',
    );
    await expectLater(
      store.moveTask(task.id, TaskStatus.review, beforeTaskId: target.id),
      throwsStateError,
    );
    expect(
      store.tasks.firstWhere((t) => t.id == task.id).status,
      TaskStatus.todo,
    );
    await store.updateTask(
      task.copyWith(projectId: two.id, title: 'Переехала'),
    );
    final moved = store.tasks.firstWhere((t) => t.id == task.id);
    expect(moved.issueNumber, 2);
    expect(moved.issueType, TaskIssueType.bug);
    expect(moved.position, greaterThan(target.position));
    await store.updateTask(moved.copyWith(issueNumber: 999, position: 999));
    expect(store.tasks.firstWhere((t) => t.id == task.id).issueNumber, 2);
    expect(
      store.tasks.firstWhere((t) => t.id == task.id).position,
      moved.position,
    );
  });

  test(
    'copy is new todo with reset checklist and no source comments/history',
    () async {
      final store = await demo();
      final source = await store.createTask(
        projectId: 'LK',
        title: 'Источник',
        issueType: TaskIssueType.story,
        dueDate: DateTime(2026, 11, 4),
        status: TaskStatus.done,
        priority: TaskPriority.high,
      );
      await store.setTaskLabels(source.id, ['MVP']);
      await store.addSubtask(source.id, 'Первый');
      await store.addSubtask(source.id, 'Второй');
      final first = store.subtasks.firstWhere((s) => s.taskId == source.id);
      await store.setSubtaskDone(first.id, true);
      await store.addComment(source.id, 'Не копировать');
      final copied = await store.duplicateTask(source.id, title: ' Копия ');
      expect(copied.id, isNot(source.id));
      expect(copied.issueNumber, isNot(source.issueNumber));
      expect(copied.title, 'Копия');
      expect(copied.status, TaskStatus.todo);
      expect(copied.completedAt, isNull);
      expect(copied.dueDate, isNull);
      expect(copied.issueType, TaskIssueType.story);
      expect(copied.priority, TaskPriority.high);
      expect(copied.labels, ['MVP']);
      final children = store.subtasks
          .where((s) => s.taskId == copied.id)
          .toList();
      expect(children.map((s) => s.title), ['Первый', 'Второй']);
      expect(children.every((s) => !s.done), isTrue);
      expect(store.comments.where((c) => c.taskId == copied.id), isEmpty);
      expect(
        store.activities
            .where((a) => a.taskId == copied.id)
            .any(
              (a) =>
                  a.body.contains('Статус:') ||
                  a.body == 'Добавлен комментарий',
            ),
        isFalse,
      );
      final minimal = await store.duplicateTask(
        source.id,
        title: 'Только родитель',
        includeSubtasks: false,
        copyDueDate: true,
      );
      expect(minimal.dueDate, source.dueDate);
      expect(store.subtasks.where((s) => s.taskId == minimal.id), isEmpty);
      final count = store.tasks.length;
      await expectLater(
        store.duplicateTask(source.id, title: 'x' * 121),
        throwsStateError,
      );
      expect(store.tasks, hasLength(count));
    },
  );

  test(
    'subtask rename preserves done/createdAt, persists and validates',
    () async {
      final store = await demo(persist: true);
      await store.addSubtask('LK-142', 'До изменения');
      final initial = store.subtasks.single;
      await store.setSubtaskDone(initial.id, true);
      await store.updateSubtask(initial.id, ' После изменения ');
      expect(store.subtasks.single.done, isTrue);
      expect(store.subtasks.single.createdAt, initial.createdAt);
      await expectLater(store.updateSubtask(initial.id, ' '), throwsStateError);
      await expectLater(
        store.updateSubtask(initial.id, 'x' * 121),
        throwsStateError,
      );
      final restored = await demo(persist: true);
      expect(restored.subtasks.single.title, 'После изменения');
      expect(restored.subtasks.single.done, isTrue);
    },
  );
}
