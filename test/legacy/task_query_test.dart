import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasko/legacy/data/task_query.dart';
import 'package:tasko/legacy/data/task_views.dart';
import 'package:tasko/legacy/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime(2026, 10, 7, 23, 59);
  const projects = [
    TaskoProject(id: 'p', name: 'Личный кабинет', key: 'LK'),
    TaskoProject(id: 'a', name: 'Архив', key: 'ARC', archived: true),
  ];
  TaskoTask task(
    String id, {
    TaskStatus status = TaskStatus.todo,
    TaskPriority priority = TaskPriority.medium,
    TaskIssueType type = TaskIssueType.task,
    DateTime? due,
    int rank = 0,
    String project = 'p',
    DateTime? created,
    String description = '',
    List<String> labels = const [],
  }) => TaskoTask(
    id: id,
    projectId: project,
    title: 'Проверка $id',
    description: description,
    status: status,
    priority: priority,
    issueType: type,
    issueNumber: int.tryParse(id),
    position: rank,
    dueDate: due,
    labels: labels,
    createdAt: created ?? DateTime(2026, 10, 1),
  );

  test('Search includes human key UUID description label and project, normalized AND words', () {
    final item = task(
      '42',
      description: 'Исправить расчёт оплаты',
      labels: ['Web'],
    );
    for (final query in [
      ' lk-42 ',
      '  РАСЧЕТ   web ',
      'личный кабинет',
      '42',
      'Проверка',
    ]) {
      expect(TaskQuery(text: query).apply([item], projects, now), [item]);
    }
    expect(
      const TaskQuery(text: 'расчет missing').apply([item], projects, now),
      isEmpty,
    );
    expect(const TaskQuery(text: '  ').apply([item], projects, now), [item]);
    final uuid = item.copyWith(id: 'a65dffa2-7e8d-4d03-a143-981259329087');
    expect(const TaskQuery(text: '981259329087').apply([uuid], projects, now), [
      uuid,
    ]);
  });

  test(
    'All categories combine with AND; done and archive have explicit inclusion',
    () {
      final item = task(
        '1',
        type: TaskIssueType.bug,
        status: TaskStatus.inProgress,
        priority: TaskPriority.urgent,
        due: DateTime(2026, 10, 6),
        labels: ['Оплата'],
      );
      final query = TaskQuery(
        projectId: 'p',
        label: 'оплата',
        issueType: TaskIssueType.bug,
        status: TaskStatus.inProgress,
        priority: TaskPriority.urgent,
        dueFilter: 1,
      );
      expect(query.apply([item, task('2')], projects, now), [item]);
      expect(
        const TaskQuery(label: 'other').apply([item], projects, now),
        isEmpty,
      );
      expect(
        const TaskQuery(projectId: 'deleted').apply([item], projects, now),
        isEmpty,
      );
      expect(
        const TaskQuery().apply(
          [task('3', project: 'a'), task('4', status: TaskStatus.done)],
          projects,
          now,
        ),
        isEmpty,
      );
      expect(
        const TaskQuery(includeArchived: true, showCompleted: true).apply(
          [task('3', project: 'a'), task('4', status: TaskStatus.done)],
          projects,
          now,
        ),
        hasLength(2),
      );
      expect(
        const TaskQuery(status: TaskStatus.done)
            .apply([task('4', status: TaskStatus.done)], projects, now),
        hasLength(1),
      );
      expect(
        const TaskQuery().apply([task('5', project: 'missing')], projects, now),
        isEmpty,
      );
    },
  );

  test('Calendar filters use local days including year boundaries and missing deadlines', () {
    final items = [
      task('1', due: DateTime(2026, 10, 7)),
      task('2', due: DateTime(2026, 10, 6)),
      task('3'),
      task('4', due: DateTime(2026, 10, 6), status: TaskStatus.done),
    ];
    expect(
      const TaskQuery(dueFilter: 2)
          .apply(items, projects, now)
          .map((t) => t.id),
      ['1'],
    );
    expect(
      const TaskQuery(
        dueFilter: 1,
        showCompleted: true,
      ).apply(items, projects, now).map((t) => t.id),
      ['2'],
    );
    expect(
      const TaskQuery(dueFilter: 3)
          .apply(items, projects, now)
          .map((t) => t.id),
      ['3'],
    );
    expect(
      const TaskQuery(dueFilter: 1).apply(
        [task('1', due: DateTime(2026, 12, 31))],
        projects,
        DateTime(2027, 1, 1),
      ),
      hasLength(1),
    );
  });

  test('Four stable sorts: manual rank independent of priority, missing dates last', () {
    final items = [
      task('a', rank: 2, priority: TaskPriority.urgent),
      task('b', rank: 0, due: DateTime(2026, 10, 8)),
      task(
        'c',
        rank: 1,
        due: DateTime(2026, 10, 7),
        created: DateTime(2026, 10, 5),
      ),
    ];
    List<String> sorted(TaskSort sort) =>
        TaskQuery(sort: sort)
            .apply(items, projects, now)
            .map((t) => t.id)
            .toList();
    expect(sorted(TaskSort.queue), ['b', 'c', 'a']);
    expect(sorted(TaskSort.dueDate), ['c', 'b', 'a']);
    expect(sorted(TaskSort.priority), ['a', 'b', 'c']);
    expect(sorted(TaskSort.newest), ['c', 'a', 'b']);
    expect(
      const TaskQuery()
          .apply([task('b'), task('a')], projects, now)
          .map((t) => t.id),
      ['a', 'b'],
    );
    final demo = task('LK-142').copyWith(issueNumber: null);
    expect(taskKey(demo, projects.first), 'LK-142');
  });

  test('Query JSON roundtrip and invalid enum/range/type rejected', () {
    const query = TaskQuery(
      text: 'LK-42 Web',
      status: TaskStatus.blocked,
      issueType: TaskIssueType.bug,
      priority: TaskPriority.high,
      label: 'Web',
      projectId: 'p',
      dueFilter: 1,
      includeArchived: true,
      showCompleted: true,
      groupByProject: true,
      sort: TaskSort.priority,
    );
    expect(TaskQuery.fromJson(query.toJson()).toJson(), query.toJson());
    for (final invalid in [
      {'dueFilter': -1},
      {'dueFilter': 4},
      {'issueType': 'epic'},
      {'sort': 'random'},
      {'showCompleted': 'true'},
      {'text': List.filled(501, 'x').join()},
    ]) {
      expect(() => TaskQuery.fromJson(invalid), throwsA(anything));
    }
  });

  test('Views persist conditions and isolate demo/two accounts, deletion idempotent', () async {
    const demo = TaskViews('demo'),
        a = TaskViews('account-a'),
        b = TaskViews('account-b');
    final saved = await a.save(
      'Ошибки',
      const TaskQuery(
        issueType: TaskIssueType.bug,
        priority: TaskPriority.high,
      ),
    );
    expect((await a.load()).single.query.issueType, TaskIssueType.bug);
    expect(await demo.load(), isEmpty);
    expect(await b.load(), isEmpty);
    await b.save('Ошибки', const TaskQuery(dueFilter: 1));
    await a.delete(saved.single.id);
    await a.delete(saved.single.id);
    expect(await a.load(), isEmpty);
    expect(await b.load(), hasLength(1));
  });

  test(
    'Parallel view mutations across instances serialized without lost entries',
    () async {
      await Future.wait([
        for (var i = 0; i < 10; i++)
          TaskViews('parallel').save('Вид $i', TaskQuery(dueFilter: i % 4)),
      ]);
      expect(await const TaskViews('parallel').load(), hasLength(10));
      await expectLater(
        const TaskViews('parallel').save('11', const TaskQuery()),
        throwsArgumentError,
      );
      final views = await const TaskViews('parallel').load();
      await Future.wait([
        for (final view in views) const TaskViews('parallel').delete(view.id),
      ]);
      expect(await const TaskViews('parallel').load(), isEmpty);
      await const TaskViews('parallel').save('После ошибки', const TaskQuery());
    },
  );

  test(
    'Invalid saved query is rejected without losing existing views',
    () async {
      const repo = TaskViews('validation');
      await repo.save('Рабочий вид', const TaskQuery(text: 'оплата'));
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getString(repo.storageKey);
      for (final invalid in [
        TaskQuery(text: List.filled(501, 'x').join()),
        const TaskQuery(dueFilter: 4),
        TaskQuery(label: List.filled(25, 'я').join()),
      ]) {
        await expectLater(
          repo.save('Некорректный', invalid),
          throwsArgumentError,
        );
        expect(prefs.getString(repo.storageKey), previous);
        expect((await repo.load()).single.name, 'Рабочий вид');
      }
      await repo.save('После ошибки', const TaskQuery());
      expect(await repo.load(), hasLength(2));
    },
  );

  test(
    'Views validate names and corrupted cache preserves other valid views',
    () async {
      const repo = TaskViews('demo');
      for (final name in ['', '   ', List.filled(41, 'я').join()]) {
        await expectLater(
          repo.save(name, const TaskQuery()),
          throwsArgumentError,
        );
      }
      await repo.save(' Расчёт ', const TaskQuery());
      await expectLater(
        repo.save('РАСЧЕТ', const TaskQuery()),
        throwsArgumentError,
      );
      final prefs = await SharedPreferences.getInstance();
      final valid = (await repo.load()).single.toJson();
      await prefs.setString(
        repo.storageKey,
        jsonEncode([
          {
            'id': 'bad',
            'name': 'bad',
            'query': {'status': 'nope'},
          },
          valid,
          valid,
          {'id': 'empty', 'name': ' ', 'query': {}},
        ]),
      );
      expect(await repo.load(), hasLength(1));
      await prefs.setString(repo.storageKey, '{broken');
      expect(await repo.load(), isEmpty);
      await repo.save('Восстановлено', const TaskQuery());
      expect(await repo.load(), hasLength(1));
    },
  );
}
