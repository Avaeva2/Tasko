import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'project archive persists without deleting tasks or detail records',
    () async {
      final store = TaskoStore();
      addTearDown(store.dispose);
      await store.initialize();
      await store.enterDemo();
      final project = await store.createProject(
        name: 'Архивируемый проект',
        key: 'ARC',
      );
      final task = await store.createTask(
        projectId: project.id,
        title: 'Незавершённая задача',
      );
      await store.addSubtask(task.id, 'Не потерять пункт');
      await store.addComment(task.id, 'Не потерять комментарий');
      await store.setProjectArchived(project.id, true);
      expect(
        store.projects.firstWhere((p) => p.id == project.id).archived,
        isTrue,
      );
      expect(
        store.tasks.any((t) => t.id == task.id && t.status == TaskStatus.todo),
        isTrue,
      );
      expect(store.subtasks, hasLength(1));
      expect(store.comments, hasLength(1));
      // An existing editor without the new field must not silently unarchive.
      await store.updateProject(
        TaskoProject(id: project.id, name: 'Обновлённый архив', key: 'ARC'),
      );
      expect(
        store.projects.firstWhere((p) => p.id == project.id).archived,
        isTrue,
      );
      final second = TaskoStore();
      addTearDown(second.dispose);
      await second.initialize();
      await second.enterDemo();
      expect(
        second.projects.firstWhere((p) => p.id == project.id).archived,
        isTrue,
      );
      expect(second.tasks.any((t) => t.id == task.id), isTrue);
      expect(second.comments, hasLength(1));
      await second.setProjectArchived(project.id, false);
      expect(
        second.projects.firstWhere((p) => p.id == project.id).archived,
        isFalse,
      );
      expect(second.subtasks, hasLength(1));
    },
  );

  test(
    'read reminder persistence uses account UUID and cannot leak into demo',
    () async {
      final auth = _SessionAuth();
      final client = _SessionClient(auth);
      final store = TaskoStore(client: client);
      addTearDown(() async {
        store.dispose();
        await client.dispose();
        await auth.dispose();
      });
      await store.initialize();
      auth.installSession();
      // Simulate a completed Auth load without making a backend HTTP request.
      store.isAuthenticated = true;
      await store.markRemindersRead(['remote-task:2026-10-09']);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(
          'tasko.reminders.read.11111111-1111-1111-1111-111111111111',
        ),
        ['remote-task:2026-10-09'],
      );
      await store.enterDemo();
      expect(store.readReminderIds, isEmpty);
      await store.markRemindersRead(['LK-142:2026-10-09']);
      expect(prefs.getStringList('tasko.reminders.read.demo'), [
        'LK-142:2026-10-09',
      ]);
      expect(
        prefs.getStringList(
          'tasko.reminders.read.11111111-1111-1111-1111-111111111111',
        ),
        ['remote-task:2026-10-09'],
      );
    },
  );

  test('copyWith preserves labels and can explicitly clear nullable dates', () {
    final original = TaskoTask(
      id: 'task',
      projectId: 'LK',
      title: 'Задача',
      labels: const ['Дизайн'],
      status: TaskStatus.done,
      dueDate: DateTime(2026, 10, 9),
      completedAt: DateTime(2026, 10, 8),
      createdAt: DateTime(2026, 10, 1),
    );
    final renamed = original.copyWith(title: 'Новое название');
    expect(renamed.labels, ['Дизайн']);
    expect(renamed.dueDate, original.dueDate);
    expect(renamed.completedAt, original.completedAt);
    expect(original.copyWith(dueDate: null, completedAt: null).dueDate, isNull);
    expect(
      original.copyWith(dueDate: null, completedAt: null).completedAt,
      isNull,
    );
  });

  test(
    'details persist across restart, record real actions and cascade with task',
    () async {
      final store = TaskoStore();
      addTearDown(store.dispose);
      await store.initialize();
      await store.enterDemo();
      expect(store.activities, isEmpty); // No fabricated historical events.
      final task = await store.createTask(
        projectId: 'LK',
        title: 'Подробная задача',
      );
      await store.setTaskLabels(task.id, [' Дизайн ', 'MVP']);
      await store.addSubtask(task.id, ' Проверить форму ');
      final subtask = store.subtasks.single;
      await store.setSubtaskDone(subtask.id, true);
      await store.addComment(task.id, ' Всё готово ');
      await store.saveProfile('Новое имя', 'Автор');
      await store.moveTask(task.id, TaskStatus.review);
      expect(store.tasks.firstWhere((t) => t.id == task.id).labels, [
        'Дизайн',
        'MVP',
      ]);
      expect(store.comments.single.authorName, 'Мария Соколова');
      expect(store.activities.last.actorName, 'Новое имя');
      await store.loadTaskDetails(task.id);
      final second = TaskoStore();
      addTearDown(second.dispose);
      await second.initialize();
      await second.enterDemo();
      await second.loadTaskDetails(task.id);
      expect(second.subtasks.single.title, 'Проверить форму');
      expect(second.subtasks.single.done, isTrue);
      expect(second.comments.single.body, 'Всё готово');
      expect(second.comments.single.authorName, 'Мария Соколова');
      expect(
        second.activities.where((a) => a.taskId == task.id).map((a) => a.body),
        contains('Добавлен комментарий'),
      );
      await second.setSubtaskDone(subtask.id, false);
      expect(second.subtasks.single.done, isFalse);
      await second.deleteSubtask(subtask.id);
      expect(second.subtasks, isEmpty);
      expect(second.activities.last.body, contains('Удалена подзадача'));
      await second.deleteTask(task.id);
      expect(second.comments, isEmpty);
      expect(second.activities, isEmpty);
    },
  );

  test(
    'detail loads preserve other tasks; project delete removes all children',
    () async {
      final store = TaskoStore(persistDemo: false);
      addTearDown(store.dispose);
      await store.enterDemo();
      final project = await store.createProject(
        name: 'Проект с подробностями',
        key: 'DET',
      );
      final first = await store.createTask(
        projectId: project.id,
        title: 'Первая',
      );
      final second = await store.createTask(
        projectId: project.id,
        title: 'Вторая',
      );
      await store.addSubtask(first.id, 'Первый пункт');
      await store.addSubtask(second.id, 'Второй пункт');
      await store.addComment(first.id, 'Первый комментарий');
      await store.addComment(second.id, 'Второй комментарий');
      await store.loadTaskDetails(first.id);
      await store.loadTaskDetails(second.id);
      expect(store.subtasks, hasLength(2));
      expect(store.comments, hasLength(2));
      await store.deleteProject(project.id);
      expect(store.subtasks, isEmpty);
      expect(store.comments, isEmpty);
      expect(store.activities, isEmpty);
    },
  );

  test(
    'detail validation and no-op edits do not manufacture history',
    () async {
      final store = TaskoStore(persistDemo: false);
      addTearDown(store.dispose);
      await store.enterDemo();
      await expectLater(
        store.setTaskLabels('LK-142', List.generate(6, (i) => '$i')),
        throwsStateError,
      );
      await expectLater(
        store.setTaskLabels('LK-142', ['x' * 25]),
        throwsStateError,
      );
      await expectLater(
        store.setTaskLabels('LK-142', ['Метка', ' Метка ']),
        throwsStateError,
      );
      await expectLater(store.addSubtask('LK-142', ' '), throwsStateError);
      await expectLater(
        store.addComment('LK-142', 'x' * 2001),
        throwsStateError,
      );
      await expectLater(
        store.addComment('unknown', 'Комментарий'),
        throwsStateError,
      );
      expect(store.activities, isEmpty);
      await store.setTaskLabels('LK-142', ['Дизайн']);
      final count = store.activities.length;
      await store.setTaskLabels('LK-142', ['Дизайн']);
      expect(store.activities, hasLength(count));
      await store.moveTask('LK-142', TaskStatus.review);
      expect(store.tasks.firstWhere((t) => t.id == 'LK-142').labels, [
        'Дизайн',
      ]);
      await store.signOut();
      expect(store.comments, isEmpty);
      expect(store.subtasks, isEmpty);
      expect(store.activities, isEmpty);
    },
  );

  test(
    'read reminders persist in demo scope and clear on leaving session',
    () async {
      final store = TaskoStore();
      addTearDown(store.dispose);
      await store.initialize();
      await store.enterDemo();
      await store.markRemindersRead(['LK-142:2026-10-09']);
      await store.markRemindersRead(['LK-142:2026-10-09', 'LK-140:2026-10-10']);
      expect(store.readReminderIds, hasLength(2));
      await store.signOut();
      expect(store.readReminderIds, isEmpty);
      await store.enterDemo();
      expect(store.readReminderIds, contains('LK-142:2026-10-09'));
      expect(store.readReminderIds, isNot(contains('LK-142:2026-10-10')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('tasko.reminders.read.demo'), hasLength(2));
    },
  );

  test(
    'entering demo clears a real local session even if revoke is offline',
    () async {
      final auth = _SessionAuth();
      final client = _SessionClient(auth);
      final store = TaskoStore(client: client, persistDemo: false);
      addTearDown(() async {
        store.dispose();
        await client.dispose();
        await auth.dispose();
      });
      await store.initialize();
      auth.installSession();
      expect(client.auth.currentSession, isNotNull);
      await store.enterDemo();
      expect(client.auth.currentSession, isNull);
      expect(auth.signOutCalls, 1);
      expect(store.isDemo, isTrue);
      expect(store.profile.email, 'maria@tasko.local');
      await store.signOut();
      expect(store.isAuthenticated, isFalse);
      expect(client.auth.currentSession, isNull);
    },
  );

  test('initialize does not authenticate or silently enter demo', () async {
    final store = TaskoStore(persistDemo: false);
    addTearDown(store.dispose);
    await store.initialize();
    expect(store.isAuthenticated, isFalse);
    expect(store.isDemo, isFalse);
    expect(store.hasBackend, isFalse);
    expect(store.projects, isEmpty);
    await expectLater(
      store.signIn('test@example.org', 'password'),
      throwsStateError,
    );
    expect(store.error, contains('Supabase не настроен'));
    expect(store.isAuthenticated, isFalse);
    expect(store.isDemo, isFalse);
    expect(store.busy, isFalse);
  });

  test(
    'project/task CRUD updates one dataset and cascade deletes children',
    () async {
      final store = TaskoStore(persistDemo: false);
      addTearDown(store.dispose);
      await store.enterDemo();
      final project = await store.createProject(
        name: ' Новый проект ',
        key: ' new ',
        description: ' Описание ',
        dueDate: DateTime.utc(2026, 10, 11, 23),
      );
      expect(project.name, 'Новый проект');
      expect(project.key, 'NEW');
      expect(project.description, 'Описание');
      expect(project.dueDate, DateTime(2026, 10, 11));
      final task = await store.createTask(
        projectId: project.id,
        title: ' Задача ',
        dueDate: DateTime.utc(2026, 10, 10, 21),
        priority: TaskPriority.urgent,
      );
      expect(task.title, 'Задача');
      expect(task.dueDate, DateTime(2026, 10, 10));
      expect(task.priority, TaskPriority.urgent);
      expect(store.tasks.where((t) => t.projectId == project.id), hasLength(1));
      await store.updateProject(
        TaskoProject(
          id: project.id,
          name: 'Другое название',
          key: 'NEW',
          description: 'Новое описание',
        ),
      );
      expect(
        store.projects.firstWhere((p) => p.id == project.id).name,
        'Другое название',
      );
      await store.updateTask(
        TaskoTask(
          id: task.id,
          projectId: project.id,
          title: 'Обновлённая задача',
          description: 'Детали',
          status: TaskStatus.review,
          priority: TaskPriority.low,
          createdAt: task.createdAt,
        ),
      );
      final updated = store.tasks.firstWhere((t) => t.id == task.id);
      expect(updated.title, 'Обновлённая задача');
      expect(updated.dueDate, isNull);
      expect(updated.status, TaskStatus.review);
      expect(updated.description, 'Детали');
      await store.deleteTask(task.id);
      expect(store.tasks.where((t) => t.id == task.id), isEmpty);
      final child = await store.createTask(
        projectId: project.id,
        title: 'Удалится с проектом',
      );
      await store.deleteProject(project.id);
      expect(store.projects.where((p) => p.id == project.id), isEmpty);
      expect(store.tasks.where((t) => t.id == child.id), isEmpty);
    },
  );

  test(
    'completion stores time, preserves it on edit, clears on reopening',
    () async {
      final store = TaskoStore(persistDemo: false);
      addTearDown(store.dispose);
      await store.enterDemo();
      final task = await store.createTask(
        projectId: 'LK',
        title: 'Проверка завершения',
      );
      await store.moveTask(task.id, TaskStatus.done);
      final completed = store.tasks.firstWhere((t) => t.id == task.id);
      expect(completed.completedAt, isNotNull);
      expect(completed.status, TaskStatus.done);
      await store.moveTask(task.id, TaskStatus.done);
      expect(
        store.tasks.firstWhere((t) => t.id == task.id).completedAt,
        completed.completedAt,
      );
      await store.moveTask(task.id, TaskStatus.inProgress);
      expect(
        store.tasks.firstWhere((t) => t.id == task.id).completedAt,
        isNull,
      );
      await store.moveTask(task.id, TaskStatus.blocked);
      expect(
        store.tasks.firstWhere((t) => t.id == task.id).status,
        TaskStatus.blocked,
      );
    },
  );

  test(
    'create in a selected column is atomic, including done timestamp',
    () async {
      final store = TaskoStore(persistDemo: false);
      addTearDown(store.dispose);
      await store.enterDemo();
      final before = store.tasks.length;
      final completed = await store.createTask(
        projectId: 'LK',
        title: 'Готовая сразу',
        status: TaskStatus.done,
      );
      expect(store.tasks, hasLength(before + 1));
      expect(completed.status, TaskStatus.done);
      expect(completed.completedAt, isNotNull);
      final blocked = await store.createTask(
        projectId: 'LK',
        title: 'Блокер сразу',
        status: TaskStatus.blocked,
      );
      expect(blocked.status, TaskStatus.blocked);
      expect(blocked.completedAt, isNull);
    },
  );

  test(
    'overlapping edit and moves run in order without stale title overwrite',
    () async {
      final store = TaskoStore(persistDemo: false);
      addTearDown(store.dispose);
      await store.enterDemo();
      final task = await store.createTask(
        projectId: 'LK',
        title: 'Старое название',
      );
      await Future.wait([
        store.updateTask(
          TaskoTask(
            id: task.id,
            projectId: task.projectId,
            title: 'Новое название',
            createdAt: task.createdAt,
          ),
        ),
        store.moveTask(task.id, TaskStatus.done),
        store.moveTask(task.id, TaskStatus.review),
      ]);
      final updated = store.tasks.firstWhere((t) => t.id == task.id);
      expect(updated.title, 'Новое название');
      expect(updated.status, TaskStatus.review);
      expect(updated.completedAt, isNull);
      expect(store.busy, isFalse);
    },
  );

  test(
    'a failed queued mutation does not poison later valid requests',
    () async {
      final store = TaskoStore(persistDemo: false);
      addTearDown(store.dispose);
      await store.enterDemo();
      final invalid = store.createTask(projectId: 'missing', title: 'Ошибка');
      final valid = store.createTask(projectId: 'LK', title: 'После ошибки');
      await expectLater(invalid, throwsStateError);
      final saved = await valid;
      expect(store.tasks.any((t) => t.id == saved.id), isTrue);
      expect(store.error, isNull);
      expect(store.busy, isFalse);
    },
  );

  test('overdue uses calendar day; today and completed are not overdue', () {
    TaskoTask task(TaskStatus status, DateTime? due) => TaskoTask(
      id: '1',
      projectId: 'LK',
      title: 'Срок',
      status: status,
      dueDate: due,
      createdAt: DateTime(2026, 10, 1),
    );
    final now = DateTime(2026, 10, 7, 23, 59);
    expect(task(TaskStatus.todo, DateTime(2026, 10, 6)).overdue(now), isTrue);
    expect(task(TaskStatus.todo, DateTime(2026, 10, 7)).overdue(now), isFalse);
    expect(task(TaskStatus.done, DateTime(2026, 10, 6)).overdue(now), isFalse);
    expect(task(TaskStatus.todo, null).overdue(now), isFalse);
  });

  test(
    'validation blocks invalid titles, foreign project and duplicate code',
    () async {
      final store = TaskoStore(persistDemo: false);
      addTearDown(store.dispose);
      await store.enterDemo();
      final count = store.projects.length;
      await expectLater(
        store.createProject(name: ' ', key: 'OK'),
        throwsStateError,
      );
      await expectLater(
        store.createProject(name: 'Проект', key: 'lk'),
        throwsStateError,
      );
      await expectLater(
        store.createProject(name: 'Проект', key: '12'),
        throwsStateError,
      );
      await expectLater(
        store.createTask(projectId: 'LK', title: 'x' * 121),
        throwsStateError,
      );
      await expectLater(
        store.createTask(projectId: 'unknown', title: 'Задача'),
        throwsStateError,
      );
      expect(store.projects, hasLength(count));
      expect(store.busy, isFalse);
      await store.signOut();
      await expectLater(
        store.createProject(name: 'Проект', key: 'OK'),
        throwsStateError,
      );
      expect(store.tasks, isEmpty);
      expect(store.isDemo, isFalse);
    },
  );

  test(
    'demo persists mutations/profile and requires explicit entry after restart',
    () async {
      final first = TaskoStore();
      addTearDown(first.dispose);
      await first.initialize();
      await first.enterDemo();
      final project = await first.createProject(
        name: 'Сохранённый проект',
        key: 'PST',
      );
      final task = await first.createTask(
        projectId: project.id,
        title: 'Сохранённая задача',
        dueDate: DateTime(2026, 11, 3),
      );
      await first.moveTask(task.id, TaskStatus.done);
      await first.saveProfile('Полина', 'Студент');
      await first.setTheme('dark');
      await first.setDeadlineReminders(false);
      await first.signOut();

      final second = TaskoStore();
      addTearDown(second.dispose);
      await second.initialize();
      expect(second.theme, 'dark');
      expect(second.deadlineReminders, isFalse);
      expect(second.projects, isEmpty);
      expect(second.isAuthenticated, isFalse);
      expect(second.isDemo, isFalse);
      await second.enterDemo();
      expect(
        second.projects.firstWhere((p) => p.id == project.id).name,
        'Сохранённый проект',
      );
      final restored = second.tasks.firstWhere((t) => t.id == task.id);
      expect(restored.status, TaskStatus.done);
      expect(restored.completedAt, isNotNull);
      expect(restored.dueDate, DateTime(2026, 11, 3));
      expect(second.profile.name, 'Полина');
      expect(second.profile.role, 'Студент');
      expect(second.hasBackend, isFalse);
      // A failed real sign-in does not erase the separately saved demo dataset.
      await second.signOut();
      await expectLater(
        second.signIn('missing@example.org', 'password'),
        throwsStateError,
      );
      expect(second.isAuthenticated, isFalse);
      await second.enterDemo();
      expect(second.tasks.any((t) => t.id == task.id), isTrue);
    },
  );
}

/// Fake only the session boundary; no HTTP calls or credentials are involved.
class _SessionClient extends SupabaseClient {
  _SessionClient(this.sessionAuth)
    : super(
        'http://localhost:1',
        'sb_publishable_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
  final _SessionAuth sessionAuth;
  @override
  GoTrueClient get auth => sessionAuth;
}

class _SessionAuth extends GoTrueClient {
  _SessionAuth()
    : super(url: 'http://localhost:1/auth/v1', autoRefreshToken: false);
  final _events = StreamController<AuthState>.broadcast(sync: true);
  Session? _session;
  int signOutCalls = 0;
  @override
  Session? get currentSession => _session;
  @override
  User? get currentUser => _session?.user;
  @override
  Stream<AuthState> get onAuthStateChange => _events.stream;
  void installSession() {
    _session = Session.fromJson({
      'access_token': 'test-access-token',
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': '11111111-1111-1111-1111-111111111111',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-10-07T00:00:00Z',
      },
    });
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    signOutCalls++;
    _session = null;
    _events.add(AuthState(AuthChangeEvent.signedOut, null));
    throw StateError('Remote revoke offline after local session removal');
  }

  @override
  Future<void> dispose() async {
    await _events.close();
    super.dispose();
  }
}
