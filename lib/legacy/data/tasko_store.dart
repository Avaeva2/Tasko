import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';

/// One UI contract, two deliberately separate repositories: explicit demo and
/// authenticated Supabase. A backend failure never silently enters demo mode.
class TaskoStore extends ChangeNotifier {
  // Named public client is intentionally mapped to a private field.
  TaskoStore({SupabaseClient? client, this.persistDemo = true})
    // ignore: prefer_initializing_formals
    : _client = client;

  final SupabaseClient? _client;
  final bool persistDemo;
  SharedPreferences? _prefs;
  StreamSubscription<AuthState>? _authSubscription;
  List<TaskoProject> projects = [];
  List<TaskoTask> tasks = [];
  List<TaskoSubtask> subtasks = [];
  List<TaskoComment> comments = [];
  List<TaskoActivity> activities = [];
  Set<String> readReminderIds = {};
  final Set<String> _detailsLoaded = {};
  final Map<String, int> _demoIssueCounters = {};
  TaskoProfile profile = const TaskoProfile(name: '', email: '', role: '');
  bool isDemo = false;
  bool isAuthenticated = false;
  bool busy = false;
  bool get hasBackend => _client != null;
  String? get preferenceScope => !isAuthenticated
      ? null
      : isDemo
      ? 'demo'
      : _client?.auth.currentUser?.id;
  String? error;
  String theme = 'system';
  bool deadlineReminders = true;
  static const _demoKey = 'tasko.demo.v2';
  Future<void> _pendingOperation = Future.value();
  int _sessionRevision = 0;
  int get sessionRevision => _sessionRevision;

  Future<T> _operation<T>(Future<T> Function() action) {
    final completion = Completer<T>();
    // Drag/drop can submit again before the preceding network reply arrives.
    // Keep requests and local state application in the same deterministic order.
    _pendingOperation = _pendingOperation.then((_) async {
      busy = true;
      error = null;
      notifyListeners();
      try {
        completion.complete(await action());
      } catch (exception) {
        error = _message(exception);
        completion.completeError(StateError(error!));
      } finally {
        busy = false;
        notifyListeners();
      }
    });
    return completion.future;
  }

  Future<T> _backendRequest<T>(Future<T> Function() request) async {
    final revision = _sessionRevision;
    final userId = _client!.auth.currentUser?.id;
    final result = await request();
    // Auth can expire/sign out independently while an HTTP request is pending.
    if (revision != _sessionRevision ||
        isDemo ||
        !isAuthenticated ||
        userId != _client.auth.currentUser?.id) {
      throw StateError('Сессия изменилась. Войдите снова.');
    }
    return result;
  }

  // Configured PostgREST max_rows is 1000. Use bounded pages and a stable
  // created_at/id order; never apply a partial load after the session changes.
  static const _readPageSize = 500;
  Future<List<Map<String, dynamic>>> _readAllRows(
    Future<List<Map<String, dynamic>>> Function(int from, int to) page,
  ) async {
    final revision = _sessionRevision;
    final userId = _client!.auth.currentUser?.id;
    final rows = <String, Map<String, dynamic>>{};
    for (var start = 0; ; start += _readPageSize) {
      if (revision != _sessionRevision ||
          isDemo ||
          !isAuthenticated ||
          userId != _client.auth.currentUser?.id) {
        throw StateError('Сессия изменилась. Войдите снова.');
      }
      final batch = await page(start, start + _readPageSize - 1);
      if (revision != _sessionRevision ||
          isDemo ||
          !isAuthenticated ||
          userId != _client.auth.currentUser?.id) {
        throw StateError('Сессия изменилась. Войдите снова.');
      }
      for (final row in batch) {
        rows[row['id'] as String] = row;
      }
      if (batch.length < _readPageSize) break;
    }
    return rows.values.toList();
  }

  Future<void> _signOutBackend() async {
    if (_client?.auth.currentSession == null) return;
    try {
      await _client!.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The SDK clears the local session before revoking it over the network.
      // A failed remote revoke must not retain an account behind demo/logout.
      if (_client!.auth.currentSession != null) rethrow;
    }
  }

  String _message(Object exception) {
    if (exception is ArgumentError) {
      return exception.message?.toString() ?? 'Проверьте данные формы.';
    }
    if (exception is AuthException) {
      switch (exception.code) {
        case 'invalid_credentials':
          return 'Неверный email или пароль.';
        case 'email_not_confirmed':
          return 'Подтвердите email перед входом.';
        case 'user_already_exists':
          return 'Этот email уже зарегистрирован.';
        case 'weak_password':
          return 'Пароль слишком простой. Используйте минимум 8 символов.';
        case 'over_request_rate_limit':
        case 'over_email_send_rate_limit':
          return 'Слишком много попыток. Повторите позже.';
        default:
          return 'Не удалось выполнить вход. Проверьте данные и соединение.';
      }
    }
    if (exception is PostgrestException) {
      if (exception.code == '40P01' || exception.code == '40001') {
        return 'Конфликт с другим изменением. Обновите данные и повторите действие.';
      }
      if (exception.code == '22023') {
        return 'Задача или целевая позиция изменились. Обновите данные.';
      }
      if (exception.code == '23505') {
        return 'Такой код проекта уже используется.';
      }
      if (exception.code == '23514') {
        return 'Данные не прошли проверку. Проверьте поля.';
      }
      if (exception.code == '42501' || exception.code == 'PGRST116') {
        return 'Нет доступа к записи либо она уже удалена.';
      }
      return 'Не удалось сохранить данные в Supabase. Проверьте соединение.';
    }
    if (exception is StateError) return exception.message;
    return 'Нет соединения с Supabase. Повторите попытку.';
  }

  Future<void> initialize() async {
    try {
      await _operation(() async {
        if (persistDemo) {
          _prefs = await SharedPreferences.getInstance();
          final savedTheme = _prefs!.getString('tasko.theme');
          if (['system', 'light', 'dark'].contains(savedTheme)) {
            theme = savedTheme!;
          }
          deadlineReminders =
              _prefs!.getBool('tasko.deadlineReminders') ?? true;
        }
        _authSubscription = _client?.auth.onAuthStateChange.listen((state) {
          if (!isDemo && state.event == AuthChangeEvent.signedOut) {
            _clearSession();
            notifyListeners();
          }
        });
        if (_client?.auth.currentSession != null) {
          isAuthenticated = true;
          _loadReadReminders();
          await _loadBackend();
        }
      });
    } catch (_) {
      // The UI stays usable on the Auth screen with a visible error/retry.
    }
  }

  Future<void> enterDemo() => _operation(() async {
    await _signOutBackend();
    _clearSession();
    isDemo = true;
    isAuthenticated = true;
    _loadReadReminders();
    final saved = _prefs?.getString(_demoKey);
    if (saved != null) {
      try {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        projects = (data['projects'] as List)
            .map((p) => _project(Map<String, dynamic>.from(p)))
            .toList();
        tasks = (data['tasks'] as List)
            .map((t) => _task(Map<String, dynamic>.from(t)))
            .toList();
        final savedCounters = data['issue_counters'];
        if (savedCounters is Map) {
          for (final entry in savedCounters.entries) {
            if (entry.key is String && entry.value is int && entry.value > 0) {
              _demoIssueCounters[entry.key as String] = entry.value as int;
            }
          }
        }
        subtasks = ((data['subtasks'] as List?) ?? [])
            .map((s) => _subtask(Map<String, dynamic>.from(s)))
            .toList();
        comments = ((data['comments'] as List?) ?? [])
            .map((s) => _comment(Map<String, dynamic>.from(s)))
            .toList();
        activities = ((data['activities'] as List?) ?? [])
            .map((s) => _activity(Map<String, dynamic>.from(s)))
            .toList();
        final p = data['profile'] as Map;
        profile = TaskoProfile(
          name: p['name'],
          email: p['email'],
          role: p['role'],
        );
        _upgradeDemoTasks();
        await _saveDemo();
        return;
      } catch (_) {
        // Malformed demo data cannot affect the server or block a fresh demo.
      }
    }
    _seedDemo();
    _upgradeDemoTasks();
    await _saveDemo();
  });

  Future<void> signIn(String email, String password) => _operation(() async {
    _requireBackend();
    if (email.trim().isEmpty || password.isEmpty) {
      throw ArgumentError('Введите email и пароль.');
    }
    await _client!.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    _clearSession();
    isAuthenticated = true;
    _loadReadReminders();
    await _loadBackend();
  });

  Future<void> signUp(String name, String email, String password) =>
      _operation(() async {
        _requireBackend();
        _validateText(name, 'Введите имя.', 120);
        if (email.trim().isEmpty) throw ArgumentError('Введите email.');
        if (password.length < 8) {
          throw ArgumentError('Пароль должен содержать минимум 8 символов.');
        }
        final response = await _client!.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'name': name.trim()},
        );
        _clearSession();
        isAuthenticated = response.session != null;
        projects = [];
        tasks = [];
        if (isAuthenticated) {
          _loadReadReminders();
          await _loadBackend();
        } else {
          profile = const TaskoProfile(name: '', email: '', role: '');
          error = 'Откройте письмо и подтвердите email, затем войдите.';
        }
      });

  Future<void> signOut() => _operation(() async {
    await _signOutBackend();
    _clearSession();
  });

  void _clearSession() {
    _sessionRevision++;
    isDemo = false;
    isAuthenticated = false;
    projects = [];
    tasks = [];
    subtasks = [];
    comments = [];
    activities = [];
    readReminderIds = {};
    _detailsLoaded.clear();
    _demoIssueCounters.clear();
    profile = const TaskoProfile(name: '', email: '', role: '');
  }

  void _requireBackend() {
    if (_client == null) {
      throw StateError('Supabase не настроен. Доступен отдельный демо-режим.');
    }
  }

  void _requireSession() {
    if (!isAuthenticated) throw StateError('Сначала войдите в аккаунт.');
    if (!isDemo) {
      _requireBackend();
      if (_client!.auth.currentUser == null) {
        throw StateError('Сессия завершена. Войдите снова.');
      }
    }
  }

  Future<void> saveProfile(String name, String role) => _operation(() async {
    _requireSession();
    _validateText(name, 'Введите имя.', 120);
    if (role.length > 120) {
      throw ArgumentError('Описание роли: максимум 120 символов.');
    }
    if (!isDemo) {
      await _backendRequest(
        () => _client!.from('profiles').upsert({
          'id': _client.auth.currentUser!.id,
          'name': name.trim(),
          'role': role.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    }
    profile = TaskoProfile(
      name: name.trim(),
      email: profile.email,
      role: role.trim(),
    );
    await _saveDemo();
  });

  Future<void> setTheme(String value) => _operation(() async {
    if (!['system', 'light', 'dark'].contains(value)) {
      throw ArgumentError('Неизвестная тема.');
    }
    await _prefs?.setString('tasko.theme', value);
    theme = value;
  });

  /// This preference controls in-app reminders only; it does not register push.
  Future<void> setDeadlineReminders(bool value) => _operation(() async {
    await _prefs?.setBool('tasko.deadlineReminders', value);
    deadlineReminders = value;
  });

  String? get _readReminderScope =>
      isDemo ? 'demo' : _client?.auth.currentUser?.id;
  void _loadReadReminders() {
    final scope = _readReminderScope;
    readReminderIds = scope == null
        ? {}
        : (_prefs?.getStringList('tasko.reminders.read.$scope') ?? []).toSet();
  }

  Future<void> markRemindersRead(Iterable<String> ids) => _operation(() async {
    _requireSession();
    final scope = _readReminderScope!;
    final combined = {...readReminderIds, ...ids};
    await _prefs?.setStringList(
      'tasko.reminders.read.$scope',
      combined.toList()..sort(),
    );
    readReminderIds = combined;
  });

  Future<TaskoProject> createProject({
    required String name,
    required String key,
    String description = '',
    DateTime? dueDate,
  }) => _operation(() async {
    _requireSession();
    _validateProject(name, key, description);
    final normalizedKey = key.trim().toUpperCase();
    // Shared projects can have an identical key under a different owner.
    // Supabase enforces uniqueness for the authenticated owner, not all readers.
    if (isDemo && projects.any((p) => p.key == normalizedKey)) {
      throw ArgumentError('Такой код проекта уже используется.');
    }
    var project = TaskoProject(
      id: const Uuid().v4(),
      name: name.trim(),
      key: normalizedKey,
      description: description.trim(),
      dueDate: _calendarDate(dueDate),
    );
    if (!isDemo) {
      project = _project(
        await _backendRequest(
          () => _client!
              .from('projects')
              .insert(_projectMap(project))
              .select()
              .single(),
        ),
      );
    }
    projects = [...projects, project];
    await _saveDemo();
    return project;
  });

  Future<void> updateProject(TaskoProject project) => _operation(() async {
    _requireSession();
    _validateProject(project.name, project.key, project.description);
    final previous = _findProject(project.id);
    if (isDemo &&
        projects.any(
          (p) =>
              p.id != project.id && p.key == project.key.trim().toUpperCase(),
        )) {
      throw ArgumentError('Такой код проекта уже используется.');
    }
    var saved = TaskoProject(
      id: project.id,
      name: project.name.trim(),
      key: project.key.trim().toUpperCase(),
      description: project.description.trim(),
      dueDate: _calendarDate(project.dueDate),
      teamId: previous.teamId,
      archived: previous.archived,
    );
    if (!isDemo) {
      saved = _project(
        await _backendRequest(
          () => _client!
              .from('projects')
              .update(_projectMap(saved)..remove('id'))
              .eq('id', saved.id)
              .select()
              .single(),
        ),
      );
    }
    projects = projects.map((p) => p.id == saved.id ? saved : p).toList();
    await _saveDemo();
  });

  Future<void> setProjectArchived(String id, bool archived) =>
      _operation(() async {
        _requireSession();
        final previous = _findProject(id);
        var saved = previous.copyWith(archived: archived);
        if (!isDemo) {
          saved = _project(
            await _backendRequest(
              () => _client!
                  .from('projects')
                  .update({'archived': archived})
                  .eq('id', id)
                  .select()
                  .single(),
            ),
          );
        }
        projects = projects.map((p) => p.id == id ? saved : p).toList();
        await _saveDemo();
      });

  Future<void> deleteProject(String id) => _operation(() async {
    _requireSession();
    _findProject(id);
    if (!isDemo) {
      await _backendRequest(
        () => _client!.from('projects').delete().eq('id', id).select().single(),
      );
    }
    _removeTaskDetails(
      tasks.where((t) => t.projectId == id).map((t) => t.id).toSet(),
    );
    projects = projects.where((p) => p.id != id).toList();
    tasks = tasks.where((t) => t.projectId != id).toList();
    await _saveDemo();
  });

  Future<TaskoTask> createTask({
    required String projectId,
    required String title,
    String description = '',
    TaskPriority priority = TaskPriority.medium,
    TaskStatus status = TaskStatus.todo,
    TaskIssueType issueType = TaskIssueType.task,
    DateTime? dueDate,
  }) => _operation(() async {
    _requireSession();
    _findProject(projectId);
    _validateText(title, 'Введите название задачи.', 120);
    if (description.length > 10000) {
      throw ArgumentError('Описание: максимум 10000 символов.');
    }
    var task = TaskoTask(
      id: const Uuid().v4(),
      projectId: projectId,
      title: title.trim(),
      description: description.trim(),
      priority: priority,
      status: status,
      issueType: issueType,
      completedAt: status == TaskStatus.done ? DateTime.now() : null,
      dueDate: _calendarDate(dueDate),
      createdAt: DateTime.now(),
      issueNumber: isDemo ? _nextDemoNumber(projectId) : null,
      position: isDemo ? _appendPosition(projectId, status) : 0,
    );
    if (!isDemo) {
      task = _task(
        await _backendRequest(
          () => _client!
              .from('tasks')
              .insert(
                _taskMap(task)
                  ..remove('created_at')
                  ..remove('completed_at')
                  ..remove('issue_number')
                  ..remove('position'),
              )
              .select()
              .single(),
        ),
      );
    }
    tasks = [...tasks, task];
    if (isDemo) _appendDemoActivity(task.id, 'Создана задача «${task.title}»');
    await _saveDemo();
    return task;
  });

  Future<void> updateTask(TaskoTask task) =>
      _operation(() => _updateTask(task));

  Future<void> _updateTask(TaskoTask task) async {
    _requireSession();
    _findProject(task.projectId);
    final previous = _findTask(task.id);
    _validateText(task.title, 'Введите название задачи.', 120);
    final labels = _validatedLabels(task.labels);
    if (task.description.length > 10000) {
      throw ArgumentError('Описание: максимум 10000 символов.');
    }
    var saved = TaskoTask(
      id: task.id,
      projectId: task.projectId,
      title: task.title.trim(),
      description: task.description.trim(),
      status: task.status,
      priority: task.priority,
      dueDate: _calendarDate(task.dueDate),
      completedAt: task.status == TaskStatus.done
          ? (previous.status == TaskStatus.done
                ? previous.completedAt
                : DateTime.now())
          : null,
      createdAt: previous.createdAt,
      labels: labels,
      issueType: task.issueType,
      issueNumber: isDemo && previous.projectId != task.projectId
          ? _nextDemoNumber(task.projectId)
          : previous.issueNumber,
      position:
          isDemo &&
              (previous.projectId != task.projectId ||
                  previous.status != task.status)
          ? _appendPosition(task.projectId, task.status)
          : previous.position,
    );
    if (!isDemo) {
      final response = await _backendRequest(
        () => _client!.rpc(
          'update_task',
          params: {
            'p_task_id': saved.id,
            'p_project_id': saved.projectId,
            'p_title': saved.title,
            'p_description': saved.description,
            'p_status': saved.status.db,
            'p_priority': saved.priority.name,
            'p_due_date': _dateString(saved.dueDate),
            'p_labels': saved.labels,
            'p_issue_type': saved.issueType.name,
          },
        ),
      );
      saved = _task(
        Map<String, dynamic>.from(
          response is List ? response.single : response as Map,
        ),
      );
    }
    tasks = tasks.map((t) => t.id == saved.id ? saved : t).toList();
    if (isDemo) {
      _logDemoTaskChange(previous, saved);
    } else if (_detailsLoaded.contains(task.id)) {
      await _refreshDetailsAfterWrite(task.id);
    }
    await _saveDemo();
  }

  Future<void> moveTask(String id, TaskStatus status, {String? beforeTaskId}) =>
      _operation(() async {
        _requireSession();
        final t = _findTask(id);
        if (beforeTaskId == id) return;
        if (isDemo) {
          final destination =
              tasks
                  .where(
                    (task) =>
                        task.projectId == t.projectId && task.status == status,
                  )
                  .toList()
                ..sort(_rankCompare);
          final ordered = destination.where((task) => task.id != id).toList();
          final insertion = beforeTaskId == null
              ? ordered.length
              : ordered.indexWhere((task) => task.id == beforeTaskId);
          if (insertion < 0) {
            throw ArgumentError(
              'Целевая задача удалена или находится в другой колонке. Обновите данные.',
            );
          }
          ordered.insert(insertion, t);
          if (t.status == status &&
              listEquals(
                destination.map((task) => task.id).toList(),
                ordered.map((task) => task.id).toList(),
              )) {
            return;
          }
          final replacements = <String, TaskoTask>{};
          for (var index = 0; index < ordered.length; index++) {
            final item = ordered[index];
            replacements[item.id] = item.copyWith(
              position: index + 1,
              status: status,
              completedAt: item.id == id
                  ? (status == TaskStatus.done
                        ? t.completedAt ?? DateTime.now()
                        : null)
                  : item.completedAt,
            );
          }
          tasks = tasks.map((task) => replacements[task.id] ?? task).toList();
          final moved = replacements[id]!;
          _logDemoTaskChange(t, moved);
          if (t.position != moved.position) {
            _appendDemoActivity(id, 'Изменён порядок задачи');
          }
          await _saveDemo();
        } else {
          final response = await _backendRequest(
            () => _client!.rpc(
              'move_task',
              params: {
                'p_task_id': id,
                'p_status': status.db,
                'p_before_task_id': beforeTaskId,
              },
            ),
          );
          final rows = (response as List)
              .map((row) => _task(Map<String, dynamic>.from(row)))
              .toList();
          tasks = mergeMovedTaskSnapshot(tasks, rows, movedTaskId: id);
          if (_detailsLoaded.contains(id)) await _refreshDetailsAfterWrite(id);
        }
      });

  /// RPC returns the actual server project. Another client may have moved the
  /// source after we read it, so the cached source project is not authoritative.
  @visibleForTesting
  static List<TaskoTask> mergeMovedTaskSnapshot(
    List<TaskoTask> current,
    List<TaskoTask> snapshot, {
    required String movedTaskId,
  }) {
    final returnedProjects = snapshot.map((task) => task.projectId).toSet();
    final merged = <String, TaskoTask>{
      for (final task in current)
        if (task.id != movedTaskId &&
            !returnedProjects.contains(task.projectId))
          task.id: task,
    };
    for (final task in snapshot) {
      merged[task.id] = task;
    }
    return merged.values.toList();
  }

  Future<TaskoTask> duplicateTask(
    String id, {
    required String title,
    bool includeSubtasks = true,
    bool copyDueDate = false,
  }) => _operation(() async {
    _requireSession();
    final source = _findTask(id);
    _validateText(title, 'Введите название копии.', 120);
    late TaskoTask copied;
    if (isDemo) {
      copied = source.copyWith(
        id: const Uuid().v4(),
        title: title.trim(),
        status: TaskStatus.todo,
        dueDate: copyDueDate ? source.dueDate : null,
        completedAt: null,
        createdAt: DateTime.now(),
        issueNumber: _nextDemoNumber(source.projectId),
        position: _appendPosition(source.projectId, TaskStatus.todo),
        labels: List.unmodifiable(source.labels),
      );
      final clonedChildren = includeSubtasks
          ? subtasks
                .where((s) => s.taskId == id)
                .map(
                  (s) => TaskoSubtask(
                    id: const Uuid().v4(),
                    taskId: copied.id,
                    title: s.title,
                    done: false,
                    createdAt: DateTime.now(),
                  ),
                )
                .toList()
          : <TaskoSubtask>[];
      tasks = [...tasks, copied];
      subtasks = [...subtasks, ...clonedChildren];
      _appendDemoActivity(copied.id, 'Создана задача «${copied.title}»');
      for (final child in clonedChildren) {
        _appendDemoActivity(copied.id, 'Добавлена подзадача «${child.title}»');
      }
      await _saveDemo();
    } else {
      final result = await _backendRequest(
        () => _client!.rpc(
          'duplicate_task',
          params: {
            'p_task_id': id,
            'p_title': title.trim(),
            'p_include_subtasks': includeSubtasks,
            'p_copy_due_date': copyDueDate,
          },
        ),
      );
      copied = _task(
        Map<String, dynamic>.from(
          result is List ? result.single : result as Map,
        ),
      );
      tasks = [...tasks, copied];
      await _refreshDetailsAfterWrite(copied.id);
    }
    return copied;
  });

  Future<void> updateSubtask(String id, String title) => _operation(() async {
    _requireSession();
    final old = _findSubtask(id);
    _findTask(old.taskId);
    _validateText(title, 'Введите название подзадачи.', 120);
    var value = TaskoSubtask(
      id: old.id,
      taskId: old.taskId,
      title: title.trim(),
      done: old.done,
      createdAt: old.createdAt,
    );
    if (!isDemo) {
      value = _subtask(
        await _backendRequest(
          () => _client!
              .from('task_subtasks')
              .update({'title': title.trim()})
              .eq('id', id)
              .select()
              .single(),
        ),
      );
    }
    subtasks = subtasks.map((s) => s.id == id ? value : s).toList();
    if (isDemo && old.title != value.title) {
      _appendDemoActivity(old.taskId, 'Изменено название подзадачи');
    }
    if (!isDemo) await _refreshDetailsAfterWrite(old.taskId);
    await _saveDemo();
  });

  Future<void> deleteTask(String id) => _operation(() async {
    _requireSession();
    _findTask(id);
    if (!isDemo) {
      await _backendRequest(
        () => _client!.from('tasks').delete().eq('id', id).select().single(),
      );
    }
    _removeTaskDetails({id});
    tasks = tasks.where((t) => t.id != id).toList();
    await _saveDemo();
  });

  Future<void> refresh() => _operation(() async {
    _requireSession();
    if (!isDemo) await _loadBackend();
  });

  Future<void> loadTaskDetails(String taskId) =>
      _operation(() => _loadTaskDetails(taskId));

  Future<void> _loadTaskDetails(String taskId) async {
    _requireSession();
    _findTask(taskId);
    if (!isDemo) {
      final rows = await _backendRequest(
        () => Future.wait([
          _readAllRows(
            (from, to) => _client!
                .from('task_subtasks')
                .select()
                .eq('task_id', taskId)
                .order('created_at', ascending: true)
                .order('id', ascending: true)
                .range(from, to),
          ),
          _readAllRows(
            (from, to) => _client!
                .from('task_comments')
                .select()
                .eq('task_id', taskId)
                .order('created_at', ascending: true)
                .order('id', ascending: true)
                .range(from, to),
          ),
          _readAllRows(
            (from, to) => _client!
                .from('task_activities')
                .select()
                .eq('task_id', taskId)
                .order('created_at', ascending: true)
                .order('id', ascending: true)
                .range(from, to),
          ),
        ]),
      );
      subtasks = [
        ...subtasks.where((s) => s.taskId != taskId),
        ...rows[0].map(_subtask),
      ];
      comments = [
        ...comments.where((s) => s.taskId != taskId),
        ...rows[1].map(_comment),
      ];
      activities = [
        ...activities.where((s) => s.taskId != taskId),
        ...rows[2].map(_activity),
      ];
    }
    _detailsLoaded.add(taskId);
  }

  Future<void> _refreshDetailsAfterWrite(String taskId) async {
    try {
      await _loadTaskDetails(taskId);
    } catch (exception) {
      if (!isAuthenticated) rethrow;
      // The write succeeded. Do not invite the UI to retry and duplicate it.
      error = 'Изменение сохранено. Не удалось обновить историю — повторите загрузку.';
    }
  }

  Future<void> addSubtask(String taskId, String title) => _operation(() async {
    _requireSession();
    _findTask(taskId);
    _validateText(title, 'Введите название подзадачи.', 120);
    var entry = TaskoSubtask(
      id: const Uuid().v4(),
      taskId: taskId,
      title: title.trim(),
      createdAt: DateTime.now(),
    );
    if (!isDemo) {
      entry = _subtask(
        await _backendRequest(
          () => _client!
              .from('task_subtasks')
              .insert({'task_id': taskId, 'title': title.trim()})
              .select()
              .single(),
        ),
      );
    }
    subtasks = [...subtasks, entry];
    if (isDemo) {
      _appendDemoActivity(taskId, 'Добавлена подзадача «${entry.title}»');
    } else {
      await _refreshDetailsAfterWrite(taskId);
    }
    await _saveDemo();
  });

  Future<void> setSubtaskDone(String id, bool done) => _operation(() async {
    _requireSession();
    final previous = _findSubtask(id);
    _findTask(previous.taskId);
    var entry = TaskoSubtask(
      id: previous.id,
      taskId: previous.taskId,
      title: previous.title,
      done: done,
      createdAt: previous.createdAt,
    );
    if (!isDemo) {
      entry = _subtask(
        await _backendRequest(
          () => _client!
              .from('task_subtasks')
              .update({'done': done})
              .eq('id', id)
              .select()
              .single(),
        ),
      );
    }
    subtasks = subtasks.map((s) => s.id == id ? entry : s).toList();
    if (isDemo && previous.done != done) {
      _appendDemoActivity(
        entry.taskId,
        '${done ? 'Выполнена' : 'Открыта повторно'} подзадача «${entry.title}»',
      );
    }
    if (!isDemo) await _refreshDetailsAfterWrite(entry.taskId);
    await _saveDemo();
  });

  Future<void> deleteSubtask(String id) => _operation(() async {
    _requireSession();
    final previous = _findSubtask(id);
    _findTask(previous.taskId);
    if (!isDemo) {
      await _backendRequest(
        () => _client!
            .from('task_subtasks')
            .delete()
            .eq('id', id)
            .select()
            .single(),
      );
    }
    subtasks = subtasks.where((s) => s.id != id).toList();
    if (isDemo) {
      _appendDemoActivity(
        previous.taskId,
        'Удалена подзадача «${previous.title}»',
      );
    } else {
      await _refreshDetailsAfterWrite(previous.taskId);
    }
    await _saveDemo();
  });

  Future<void> addComment(String taskId, String body) => _operation(() async {
    _requireSession();
    _findTask(taskId);
    _validateText(body, 'Введите комментарий.', 2000);
    var entry = TaskoComment(
      id: const Uuid().v4(),
      taskId: taskId,
      authorName: profile.name,
      body: body.trim(),
      createdAt: DateTime.now(),
    );
    if (!isDemo) {
      entry = _comment(
        await _backendRequest(
          () => _client!
              .from('task_comments')
              .insert({'task_id': taskId, 'body': body.trim()})
              .select()
              .single(),
        ),
      );
    }
    comments = [...comments, entry];
    if (isDemo) {
      _appendDemoActivity(taskId, 'Добавлен комментарий');
    } else {
      await _refreshDetailsAfterWrite(taskId);
    }
    await _saveDemo();
  });

  Future<void> setTaskLabels(String taskId, List<String> labels) =>
      _operation(() async {
        final task = _findTask(taskId);
        await _updateTask(task.copyWith(labels: _validatedLabels(labels)));
      });

  List<String> _validatedLabels(List<String> labels) {
    final normalized = labels.map((label) => label.trim()).toList();
    if (normalized.length > 5) {
      throw ArgumentError('Можно добавить максимум 5 меток.');
    }
    if (normalized.any((label) => label.isEmpty || label.length > 24)) {
      throw ArgumentError('Метка: от 1 до 24 символов.');
    }
    if (normalized.toSet().length != normalized.length) {
      throw ArgumentError('Метки не должны повторяться.');
    }
    return List.unmodifiable(normalized);
  }

  TaskoSubtask _findSubtask(String id) => subtasks.firstWhere(
    (s) => s.id == id,
    orElse: () => throw ArgumentError('Подзадача не найдена. Обновите данные.'),
  );

  void _removeTaskDetails(Set<String> taskIds) {
    subtasks = subtasks.where((s) => !taskIds.contains(s.taskId)).toList();
    comments = comments.where((s) => !taskIds.contains(s.taskId)).toList();
    activities = activities.where((s) => !taskIds.contains(s.taskId)).toList();
    _detailsLoaded.removeAll(taskIds);
    readReminderIds.removeWhere(
      (key) => taskIds.any((id) => key.startsWith('$id:')),
    );
  }

  void _appendDemoActivity(String taskId, String body) {
    activities = [
      ...activities,
      TaskoActivity(
        id: const Uuid().v4(),
        taskId: taskId,
        actorName: profile.name,
        body: body,
        createdAt: DateTime.now(),
      ),
    ];
  }

  void _logDemoTaskChange(TaskoTask old, TaskoTask value) {
    if (old.status != value.status) {
      _appendDemoActivity(
        value.id,
        'Статус: «${old.status.label}» → «${value.status.label}»',
      );
    }
    if (old.title != value.title) {
      _appendDemoActivity(value.id, 'Изменено название задачи');
    }
    if (old.description != value.description) {
      _appendDemoActivity(value.id, 'Изменено описание задачи');
    }
    if (old.dueDate != value.dueDate) {
      _appendDemoActivity(
        value.id,
        value.dueDate == null
            ? 'Срок задачи снят'
            : 'Срок задачи: ${_dateString(value.dueDate)}',
      );
    }
    if (old.priority != value.priority) {
      _appendDemoActivity(value.id, 'Изменён приоритет задачи');
    }
    if (!listEquals(old.labels, value.labels)) {
      _appendDemoActivity(value.id, 'Обновлены метки задачи');
    }
    if (old.issueType != value.issueType) {
      _appendDemoActivity(value.id, 'Изменён тип задачи');
    }
    if (old.projectId != value.projectId) {
      _appendDemoActivity(value.id, 'Задача перенесена в другой проект');
    }
  }

  static TaskoSubtask _subtask(Map<String, dynamic> value) => TaskoSubtask(
    id: value['id'] as String,
    taskId: value['task_id'] as String,
    title: value['title'] as String,
    done: value['done'] as bool,
    createdAt: DateTime.parse(value['created_at'] as String).toLocal(),
  );
  static TaskoComment _comment(Map<String, dynamic> value) => TaskoComment(
    id: value['id'] as String,
    taskId: value['task_id'] as String,
    authorName: value['author_name'] as String,
    body: value['body'] as String,
    createdAt: DateTime.parse(value['created_at'] as String).toLocal(),
  );
  static TaskoActivity _activity(Map<String, dynamic> value) => TaskoActivity(
    id: value['id'] as String,
    taskId: value['task_id'] as String,
    actorName: value['actor_name'] as String,
    body: value['body'] as String,
    createdAt: DateTime.parse(value['created_at'] as String).toLocal(),
  );
  static Map<String, dynamic> _subtaskMap(TaskoSubtask value) => {
    'id': value.id,
    'task_id': value.taskId,
    'title': value.title,
    'done': value.done,
    'created_at': value.createdAt.toUtc().toIso8601String(),
  };
  static Map<String, dynamic> _commentMap(TaskoComment value) => {
    'id': value.id,
    'task_id': value.taskId,
    'author_name': value.authorName,
    'body': value.body,
    'created_at': value.createdAt.toUtc().toIso8601String(),
  };
  static Map<String, dynamic> _activityMap(TaskoActivity value) => {
    'id': value.id,
    'task_id': value.taskId,
    'actor_name': value.actorName,
    'body': value.body,
    'created_at': value.createdAt.toUtc().toIso8601String(),
  };

  Future<void> _loadBackend() async {
    final user = _client!.auth.currentUser;
    if (user == null) throw StateError('Сессия завершена. Войдите снова.');
    // Replace UI state only when all requests succeed.
    final results = await _backendRequest(
      () => Future.wait([
        _readAllRows(
          (from, to) => _client
              .from('projects')
              .select()
              .order('created_at', ascending: true)
              .order('id', ascending: true)
              .range(from, to),
        ),
        _readAllRows(
          (from, to) => _client
              .from('tasks')
              .select()
              .order('created_at', ascending: true)
              .order('id', ascending: true)
              .range(from, to),
        ),
        _readAllRows(
          (from, to) => _client
              .from('profiles')
              .select()
              .eq('id', user.id)
              .order('id', ascending: true)
              .range(from, to),
        ),
      ]),
    );
    final loadedProfiles = results[2];
    if (loadedProfiles.isEmpty) {
      throw StateError('Профиль не создан. Проверьте миграции Supabase.');
    }
    projects = results[0].map(_project).toList();
    tasks = results[1].map(_task).toList();
    final allowedIds = tasks.map((t) => t.id).toSet();
    _removeTaskDetails(
      _detailsLoaded.where((id) => !allowedIds.contains(id)).toSet(),
    );
    profile = TaskoProfile(
      name: loadedProfiles.first['name'] as String,
      email: user.email ?? '',
      role: loadedProfiles.first['role'] as String,
    );
  }

  TaskoProject _findProject(String id) => projects.firstWhere(
    (p) => p.id == id,
    orElse: () => throw ArgumentError('Проект не найден. Обновите данные.'),
  );
  TaskoTask _findTask(String id) => tasks.firstWhere(
    (t) => t.id == id,
    orElse: () => throw ArgumentError('Задача не найдена. Обновите данные.'),
  );

  void _validateText(String text, String emptyMessage, int limit) {
    if (text.trim().isEmpty) throw ArgumentError(emptyMessage);
    if (text.trim().length > limit) {
      throw ArgumentError('Максимум $limit символов.');
    }
  }

  void _validateProject(String name, String key, String description) {
    _validateText(name, 'Введите название проекта.', 120);
    if (!RegExp(r'^[A-Z][A-Z0-9]{1,9}$').hasMatch(key.trim().toUpperCase())) {
      throw ArgumentError('Код: 2–10 латинских букв или цифр, первая — буква.');
    }
    if (description.length > 10000) {
      throw ArgumentError('Описание: максимум 10000 символов.');
    }
  }

  static DateTime? _calendarDate(DateTime? date) =>
      date == null ? null : DateTime(date.year, date.month, date.day);
  static String? _dateString(DateTime? date) => date == null
      ? null
      : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  static DateTime? _parseDate(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);
  static TaskoProject _project(Map<String, dynamic> p) => TaskoProject(
    id: p['id'] as String,
    name: p['name'] as String,
    key: p['key'] as String,
    description: p['description'] as String? ?? '',
    dueDate: _parseDate(p['due_date']),
    teamId: p['team_id'] as String?,
    archived: p['archived'] as bool? ?? false,
  );
  static TaskoTask _task(Map<String, dynamic> t) => TaskoTask(
    id: t['id'] as String,
    projectId: t['project_id'] as String,
    title: t['title'] as String,
    description: t['description'] as String? ?? '',
    status: TaskStatus.values.firstWhere((s) => s.db == t['status']),
    priority: TaskPriority.values.byName(t['priority'] as String),
    dueDate: _parseDate(t['due_date']),
    completedAt: _parseDate(t['completed_at'])?.toLocal(),
    createdAt: DateTime.parse(t['created_at'] as String).toLocal(),
    labels: List<String>.from(t['labels'] as List? ?? []),
    issueType:
        TaskIssueType.values
            .where((type) => type.name == t['issue_type'])
            .firstOrNull ??
        TaskIssueType.task,
    issueNumber: (t['issue_number'] as num?)?.toInt(),
    position: (t['position'] as num?)?.toInt() ?? 0,
  );
  static Map<String, dynamic> _projectMap(TaskoProject p) => {
    'id': p.id,
    'name': p.name,
    'key': p.key,
    'description': p.description,
    'due_date': _dateString(p.dueDate),
    'team_id': p.teamId,
    'archived': p.archived,
  };
  static Map<String, dynamic> _taskMap(TaskoTask t) => {
    'id': t.id,
    'project_id': t.projectId,
    'title': t.title,
    'description': t.description,
    'status': t.status.db,
    'priority': t.priority.name,
    'due_date': _dateString(t.dueDate),
    'completed_at': t.completedAt?.toUtc().toIso8601String(),
    'created_at': t.createdAt.toUtc().toIso8601String(),
    'labels': t.labels,
    'issue_type': t.issueType.name,
    'issue_number': t.issueNumber,
    'position': t.position,
  };

  static int _rankCompare(TaskoTask a, TaskoTask b) {
    final compared = a.position.compareTo(b.position);
    return compared != 0 ? compared : a.id.compareTo(b.id);
  }

  int _appendPosition(String projectId, TaskStatus status) =>
      tasks
          .where((task) => task.projectId == projectId && task.status == status)
          .fold(
            0,
            (rank, task) => task.position > rank ? task.position : rank,
          ) +
      1;
  int _nextDemoNumber(String projectId) {
    final number = _demoIssueCounters[projectId] ?? 1;
    _demoIssueCounters[projectId] = number + 1;
    return number;
  }

  void _upgradeDemoTasks() {
    final upgraded = <String, TaskoTask>{};
    for (final projectId in tasks.map((task) => task.projectId).toSet()) {
      final group = tasks.where((task) => task.projectId == projectId).toList()
        ..sort((a, b) {
          final compared = a.createdAt.compareTo(b.createdAt);
          return compared != 0 ? compared : a.id.compareTo(b.id);
        });
      int? legacyNumber(TaskoTask task) {
        final candidate =
            task.issueNumber ??
            int.tryParse(
              RegExp(r'^[A-Z][A-Z0-9]*-(\d+)$').firstMatch(task.id)?.group(1) ??
                  '',
            );
        return candidate != null && candidate > 0 ? candidate : null;
      }

      final maximum = group.fold(0, (value, task) {
        final number = legacyNumber(task) ?? 0;
        return number > value ? number : value;
      });
      if ((_demoIssueCounters[projectId] ?? 1) <= maximum) {
        _demoIssueCounters[projectId] = maximum + 1;
      }
      _demoIssueCounters.putIfAbsent(projectId, () => 1);
      final usedNumbers = <int>{};
      final usedRanks = <TaskStatus, Set<int>>{};
      final nextRanks = <TaskStatus, int>{
        for (final status in TaskStatus.values)
          status:
              group
                  .where((task) => task.status == status)
                  .fold(
                    0,
                    (rank, task) => task.position > rank ? task.position : rank,
                  ) +
              1,
      };
      for (final task in group) {
        var number = legacyNumber(task);
        if (number == null || !usedNumbers.add(number)) {
          number = _nextDemoNumber(projectId);
          usedNumbers.add(number);
        }
        final ranks = usedRanks.putIfAbsent(task.status, () => {});
        var position = task.position;
        if (position <= 0 || !ranks.add(position)) {
          position = nextRanks[task.status]!;
          nextRanks[task.status] = position + 1;
          ranks.add(position);
        }
        upgraded[task.id] = task.copyWith(
          issueNumber: number,
          position: position,
        );
      }
    }
    tasks = tasks.map((task) => upgraded[task.id] ?? task).toList();
  }

  Future<void> _saveDemo() async {
    if (!isDemo || _prefs == null) return;
    await _prefs!.setString(
      _demoKey,
      jsonEncode({
        'projects': projects.map(_projectMap).toList(),
        'tasks': tasks.map(_taskMap).toList(),
        'issue_counters': _demoIssueCounters,
        'subtasks': subtasks.map(_subtaskMap).toList(),
        'comments': comments.map(_commentMap).toList(),
        'activities': activities.map(_activityMap).toList(),
        'profile': {
          'name': profile.name,
          'email': profile.email,
          'role': profile.role,
        },
      }),
    );
  }

  void _seedDemo() {
    profile = const TaskoProfile();
    projects = [
      TaskoProject(
        id: 'LK',
        name: 'Редизайн личного кабинета',
        key: 'LK',
        description: 'Обновляем интерфейс и делаем привычные действия проще.',
        dueDate: DateTime(2026, 10, 23),
      ),
      TaskoProject(
        id: 'CRM',
        name: 'Миграция на новую CRM',
        key: 'CRM',
        description: 'Перенос контактов и настройка процессов.',
        dueDate: DateTime(2026, 10, 30),
      ),
      TaskoProject(
        id: 'APP',
        name: 'Мобильное приложение 2.0',
        key: 'APP',
        dueDate: DateTime(2026, 11, 12),
      ),
      TaskoProject(
        id: 'FIN',
        name: 'Отчётность для финансов',
        key: 'FIN',
        dueDate: DateTime(2026, 10, 20),
      ),
    ];
    final seeds = <(String, String, TaskStatus, TaskPriority, int)>[
      (
        'LK-142',
        'Перенести форму смены тарифа на новый компонент',
        TaskStatus.inProgress,
        TaskPriority.high,
        9,
      ),
      (
        'LK-140',
        'Тесты оплаты картой «Мир» в личном кабинете',
        TaskStatus.inProgress,
        TaskPriority.high,
        10,
      ),
      (
        'LK-138',
        'Согласовать тексты ошибок оплаты с юристами',
        TaskStatus.review,
        TaskPriority.medium,
        8,
      ),
      (
        'LK-145',
        'Адаптив таблицы платежей для экранов 360 dp',
        TaskStatus.todo,
        TaskPriority.medium,
        14,
      ),
      (
        'LK-147',
        'Пустые состояния раздела «Документы»',
        TaskStatus.todo,
        TaskPriority.low,
        16,
      ),
      (
        'LK-131',
        'Восстановление доступа по SMS',
        TaskStatus.blocked,
        TaskPriority.urgent,
        6,
      ),
      (
        'LK-129',
        'Новая навигация по разделам',
        TaskStatus.done,
        TaskPriority.high,
        2,
      ),
      (
        'LK-133',
        'Аудит контраста в тёмной теме',
        TaskStatus.done,
        TaskPriority.medium,
        3,
      ),
      (
        'CRM-58',
        'Выгрузка контактов из старой CRM',
        TaskStatus.inProgress,
        TaskPriority.medium,
        12,
      ),
      (
        'CRM-61',
        'Сопоставление полей сделок',
        TaskStatus.review,
        TaskPriority.high,
        9,
      ),
      (
        'CRM-64',
        'Обучение отдела продаж',
        TaskStatus.todo,
        TaskPriority.low,
        20,
      ),
    ];
    tasks = seeds
        .map(
          (s) => TaskoTask(
            id: s.$1,
            projectId: s.$1.split('-').first,
            title: s.$2,
            description: s.$1 == 'LK-131' ? 'Ждём доступ к SMS-шлюзу' : '',
            status: s.$3,
            priority: s.$4,
            dueDate: DateTime(2026, 10, s.$5),
            completedAt: s.$3 == TaskStatus.done
                ? DateTime(2026, 10, s.$5, 15)
                : null,
            createdAt: DateTime(2026, 10, 1),
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
