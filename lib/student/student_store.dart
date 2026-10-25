import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'student_models.dart';
import 'student_board_order.dart';

/// Explicit local demo and authenticated cloud repository. Neither reads nor
/// writes PM keys/tables. A cloud failure never silently becomes a local demo.
class StudentStore extends ChangeNotifier {
  StudentStore({SupabaseClient? client, this.persistDemo = true})
    // Public named argument intentionally maps to the private client.
    // ignore: prefer_initializing_formals
    : _client = client;
  final SupabaseClient? _client;
  final bool persistDemo;
  static const demoKey = 'tasko.students.v1';

  /// Maximum TOTAL raw attachment bytes in the local JSON (base64 adds ~33%).
  static const maxDemoFileBytes = 2 * 1024 * 1024;
  static const maxCloudFileBytes = 2 * 1024 * 1024;
  static const materialBucket = 'student-materials';
  static const _uuid = Uuid();
  SharedPreferences? _prefs;
  StreamSubscription<AuthState>? _auth;
  Future<void> _pending = Future.value();
  bool _disposed = false;
  int _revision = 0;
  List<StudySubject> subjects = [];
  List<StudyClass> classes = [];
  List<StudyAssignment> assignments = [];
  StudyProfile profile = const StudyProfile();
  bool authenticated = false, isDemo = false, busy = false;
  String? error;
  bool get hasBackend => _client != null;
  bool get isAuthenticated => authenticated;
  int get sessionRevision => _revision;
  int countStatus(StudyStatus status) =>
      assignments.where((a) => a.status == status).length;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _run<T>(Future<T> Function() action) {
    final completion = Completer<T>();
    _pending = _pending.then((_) async {
      busy = true;
      error = null;
      _notify();
      try {
        completion.complete(await action());
      } catch (e, stack) {
        error = _message(e);
        completion.completeError(StateError(error!), stack);
      } finally {
        busy = false;
        _notify();
      }
    });
    return completion.future;
  }

  String _message(Object e) {
    if (e is StateError) return e.message;
    if (e is ArgumentError) return e.message?.toString() ?? 'Проверьте данные.';
    if (e is AuthException) {
      if (e.code == 'invalid_credentials') return 'Неверный email или пароль.';
      if (e.code == 'email_not_confirmed') {
        return 'Подтвердите email перед входом.';
      }
      return 'Не удалось выполнить вход: ${e.message}';
    }
    if (e is PostgrestException) {
      return 'Не удалось сохранить учебные данные. Проверьте подключение и миграцию Students.';
    }
    return 'Не удалось сохранить данные. Проверьте подключение и повторите.';
  }

  void clearError() {
    error = null;
    _notify();
  }

  StudySubject? subjectById(String id) {
    for (final s in subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  StudyClass? classById(String id) {
    for (final c in classes) {
      if (c.id == id) return c;
    }
    return null;
  }

  StudyAssignment? assignmentById(String id) {
    for (final a in assignments) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<StudyAssignment> assignmentsForSubject(String id) =>
      assignments.where((a) => a.subjectId == id).toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  List<StudyClass> classesForDay(DateTime day) =>
      classes
          .where(
            (c) =>
                c.startsAt.year == day.year &&
                c.startsAt.month == day.month &&
                c.startsAt.day == day.day,
          )
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  List<StudyAssignment> get upcomingAssignments =>
      assignments.where((a) => a.status != StudyStatus.done).toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  Future<void> initialize() async {
    try {
      await _run(() async {
        if (persistDemo) _prefs = await SharedPreferences.getInstance();
        _auth ??= _client?.auth.onAuthStateChange.listen((state) {
          if (!isDemo && state.event == AuthChangeEvent.signedOut) {
            _clear();
            _notify();
          }
        });
        if (_client?.auth.currentSession != null) {
          authenticated = true;
          try {
            await _loadCloud();
          } catch (_) {
            _clear();
            rethrow;
          }
        }
      });
    } catch (_) {
      /* Auth screen displays error; demo remains an explicit choice. */
    }
  }

  void _clear() {
    _revision++;
    authenticated = false;
    isDemo = false;
    subjects = [];
    classes = [];
    assignments = [];
    profile = const StudyProfile();
  }

  Future<void> _signOut() async {
    if (_client?.auth.currentSession != null) {
      await _client!.auth.signOut(scope: SignOutScope.local);
    }
  }

  Future<void> enterDemo() => _run(() async {
    await _signOut();
    _clear();
    final saved = _prefs?.getString(demoKey);
    if (saved != null) {
      try {
        _restore(jsonDecode(saved) as Map<String, dynamic>);
      } catch (_) {
        _clear();
        throw StateError(
          'Сохранённые учебные данные повреждены. Они не перезаписаны. Используйте явный сброс демо.',
        );
      }
    } else {
      _seed();
    }
    isDemo = true;
    authenticated = true;
    await _persist();
  });
  Future<void> resetDemo() => _run(() async {
    await _signOut();
    _clear();
    _seed();
    isDemo = true;
    authenticated = true;
    await _persist();
  });
  Future<void> logout() => _run(() async {
    await _signOut();
    _clear();
  });
  Future<void> login(String email, String password) => _run(() async {
    if (_client == null) {
      throw StateError('Supabase не настроен. Можно открыть локальное демо.');
    }
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    _clear();
    authenticated = true;
    try {
      await _loadCloud();
    } catch (_) {
      _clear();
      rethrow;
    }
  });
  Future<void> signUp(
    String email,
    String password,
    String name,
  ) => _run(() async {
    if (_client == null) {
      throw StateError('Supabase не настроен. Можно открыть локальное демо.');
    }
    if (name.trim().isEmpty) throw ArgumentError('Укажите имя.');
    if (password.length < 8) {
      throw ArgumentError('Пароль должен содержать минимум 8 символов.');
    }
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'name': name.trim()},
    );
    _clear();
    if (response.session == null) {
      throw StateError(
        'Проверьте почту и подтвердите регистрацию, затем войдите.',
      );
    }
    authenticated = true;
    try {
      await _loadCloud();
      await _saveProfile(StudyProfile(name: name.trim(), email: email.trim()));
    } catch (_) {
      _clear();
      rethrow;
    }
  });

  Map<String, dynamic> _snapshot() => {
    'version': 1,
    'profile': profile.toJson(),
    'subjects': subjects.map((e) => e.toJson()).toList(),
    'classes': classes.map((e) => e.toJson()).toList(),
    'assignments': assignments.map((e) => e.toJson()).toList(),
  };
  void _restore(Map<String, dynamic> j) {
    if (j['version'] != 1) {
      throw const FormatException('Unsupported student data');
    }
    profile = StudyProfile.fromJson(Map<String, dynamic>.from(j['profile']));
    subjects = (j['subjects'] as List)
        .map((e) => StudySubject.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    classes = (j['classes'] as List)
        .map((e) => StudyClass.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    assignments = (j['assignments'] as List)
        .map((e) => StudyAssignment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    for (final c in classes) {
      _validateClass(c);
    }
    for (final a in assignments) {
      _validateAssignment(a);
    }
    _checkBudget(assignments);
  }

  Future<void> _persist() async {
    if (!isDemo || !persistDemo) return;
    _checkBudget(assignments);
    _prefs ??= await SharedPreferences.getInstance();
    if (!await _prefs!.setString(demoKey, jsonEncode(_snapshot()))) {
      throw StateError('Не удалось записать локальные учебные данные.');
    }
  }

  void _requireSession() {
    if (!authenticated) throw StateError('Сначала войдите или откройте демо.');
  }

  Future<void> _mutate(Future<void> Function() action) async {
    _requireSession();
    final before = _snapshot();
    final revision = _revision;
    try {
      await action();
      if (_revision != revision) throw StateError('Сессия изменилась.');
      await _persist();
    } catch (_) {
      if (_revision == revision) _restore(before);
      rethrow;
    }
  }

  void _checkBudget(List<StudyAssignment> values) {
    final total = values
        .expand((a) => a.materials)
        .fold<int>(0, (n, m) => n + (m.bytes?.length ?? 0));
    if (total > maxDemoFileBytes) {
      throw ArgumentError(
        'В локальном демо все файлы вместе должны занимать не больше 2 МБ. Удалите лишние файлы.',
      );
    }
  }

  void _validateClass(StudyClass c) {
    if (subjectById(c.subjectId) == null) {
      throw ArgumentError('Выберите существующий предмет.');
    }
    if (c.title.trim().isEmpty || !c.endsAt.isAfter(c.startsAt)) {
      throw ArgumentError(
        'Укажите название пары и время окончания позже начала.',
      );
    }
  }

  void _validateAssignment(StudyAssignment a) {
    if (a.title.trim().isEmpty || a.title.length > 200) {
      throw ArgumentError('Название задания: от 1 до 200 символов.');
    }
    if (a.description.length > 2000) {
      throw ArgumentError('Описание: не больше 2000 символов.');
    }
    if (subjectById(a.subjectId) == null) {
      throw ArgumentError('Выберите существующий предмет.');
    }
    if (a.classId != null && classById(a.classId!)?.subjectId != a.subjectId) {
      throw ArgumentError(
        'Связанная пара должна относиться к выбранному предмету.',
      );
    }
    if (a.reminderMinutes != null &&
        (a.reminderMinutes! < 0 || a.reminderMinutes! > 60 * 24 * 365)) {
      throw ArgumentError('Некорректное время напоминания.');
    }
    if (a.materials.map((m) => m.id).toSet().length != a.materials.length) {
      throw ArgumentError('Материал добавлен повторно.');
    }
    for (final m in a.materials) {
      if (m.name.trim().isEmpty || m.name.length > 160) {
        throw ArgumentError('Название материала: от 1 до 160 символов.');
      }
      if (m.url != null) {
        final uri = Uri.tryParse(m.url!);
        if (m.url!.length > 2048 ||
            uri == null ||
            !['http', 'https'].contains(uri.scheme.toLowerCase()) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw ArgumentError('Укажите корректную HTTP(S)-ссылку.');
        }
        if (m.bytes != null || m.storagePath != null) {
          throw ArgumentError('Материал должен быть ссылкой или файлом.');
        }
      } else if (m.bytes == null && m.storagePath == null) {
        throw ArgumentError('Файл недоступен. Выберите файл заново.');
      }
      if (m.bytes != null && m.bytes!.length > maxCloudFileBytes) {
        throw ArgumentError('Один файл должен занимать не больше 2 МБ.');
      }
      if (m.storagePath != null &&
          !isDemo &&
          !m.storagePath!.startsWith(
            '${_client?.auth.currentUser?.id}/${a.id}/',
          )) {
        throw ArgumentError('Нет доступа к файлу задания.');
      }
    }
  }

  Future<StudyAssignment> createAssignment({
    required String title,
    required String subjectId,
    required DateTime dueAt,
    String description = '',
    String? classId,
    int? reminderMinutes = 1440,
    List<StudyMaterial> materials = const [],
    List<StudyChecklistItem> checklist = const [],
  }) => _run(() async {
    var a = StudyAssignment(
      id: _uuid.v4(),
      subjectId: subjectId,
      title: title.trim(),
      dueAt: dueAt,
      description: description.trim(),
      classId: classId,
      reminderMinutes: reminderMinutes,
      materials: materials,
      checklist: checklist,
    );
    await _mutate(() async {
      _validateAssignment(a);
      if (isDemo) {
        _checkBudget([...assignments, a]);
      } else {
        a = await _saveCloudAssignment(a);
      }
      assignments = [...assignments, a];
    });
    return a;
  });
  Future<void> updateAssignment(StudyAssignment assignment) =>
      _run(() => _mutate(() => _update(assignment)));
  Future<void> _update(StudyAssignment a) async {
    if (assignmentById(a.id) == null) {
      throw ArgumentError('Задание не найдено.');
    }
    _validateAssignment(a);
    final next = assignments.map((v) => v.id == a.id ? a : v).toList();
    if (isDemo) {
      _checkBudget(next);
    } else {
      a = await _saveCloudAssignment(a);
    }
    assignments = assignments.map((v) => v.id == a.id ? a : v).toList();
  }

  Future<void> deleteAssignment(String id) => _run(
    () => _mutate(() async {
      final a = assignmentById(id);
      if (a == null) throw ArgumentError('Задание не найдено.');
      if (!isDemo) {
        await _cloud(
          () => _client!.from('student_assignments').delete().eq('id', id),
        );
        await _cleanupFiles(a.materials);
      }
      assignments = assignments.where((v) => v.id != id).toList();
    }),
  );
  Future<void> setStatus(String id, StudyStatus status) => _run(
    () => _mutate(() async {
      final a = assignmentById(id);
      if (a == null) throw ArgumentError('Задание не найдено.');
      await _update(
        a.copyWith(
          status: status,
          completedAt: status == StudyStatus.done ? DateTime.now() : null,
        ),
      );
    }),
  );

  /// Status and exact board position persist in the same assignment update.
  Future<void> moveAssignment(
    String id,
    StudyStatus status, {
    String? afterId,
    String? beforeId,
    DateTime? completedAt,
  }) => _run(
    () => _mutate(() async {
      final assignment = assignmentById(id);
      if (assignment == null) throw ArgumentError('Задание не найдено.');
      StudyAssignment? neighbor(String? value) {
        if (value == null) return null;
        final row = assignmentById(value);
        if (row == null || row.id == id || row.status != status) {
          throw ArgumentError('Доска изменилась. Повторите перенос.');
        }
        return row;
      }

      final previous = neighbor(afterId), next = neighbor(beforeId);
      final column =
          assignments.where((a) => a.id != id && a.status == status).toList()
            ..sort(compareStudyBoard);
      final left = previous != null
          ? studyBoardOrder(previous)
          : next == null && column.isNotEmpty
          ? studyBoardOrder(column.last)
          : null;
      final right = next == null ? null : studyBoardOrder(next);
      await _update(
        assignment.copyWith(
          status: status,
          boardOrder: studyBoardBetween(left, right),
          completedAt: status == StudyStatus.done
              ? completedAt ?? DateTime.now()
              : null,
        ),
      );
    }),
  );
  Future<void> updateContext(
    String id, {
    required String description,
    required String subjectId,
    String? classId,
    required List<StudyMaterial> materials,
  }) => _run(
    () => _mutate(() async {
      final a = assignmentById(id);
      if (a == null) throw ArgumentError('Задание не найдено.');
      await _update(
        a.copyWith(
          description: description.trim(),
          subjectId: subjectId,
          classId: classId,
          materials: materials,
        ),
      );
    }),
  );
  Future<void> toggleChecklist(String id, String itemId, bool done) => _run(
    () => _mutate(() async {
      final a = assignmentById(id);
      if (a == null || !a.checklist.any((v) => v.id == itemId)) {
        throw ArgumentError('Пункт не найден.');
      }
      await _update(
        a.copyWith(
          checklist: a.checklist
              .map((v) => v.id == itemId ? v.copyWith(done: done) : v)
              .toList(),
        ),
      );
    }),
  );
  Future<void> addChecklistItem(String id, String title) => _run(
    () => _mutate(() async {
      final a = assignmentById(id);
      if (a == null || title.trim().isEmpty) {
        throw ArgumentError('Укажите пункт чеклиста.');
      }
      await _update(
        a.copyWith(
          checklist: [
            ...a.checklist,
            StudyChecklistItem(id: _uuid.v4(), title: title.trim()),
          ],
        ),
      );
    }),
  );
  Future<void> deleteChecklistItem(String id, String itemId) => _run(
    () => _mutate(() async {
      final a = assignmentById(id);
      if (a == null) throw ArgumentError('Задание не найдено.');
      await _update(
        a.copyWith(
          checklist: a.checklist.where((v) => v.id != itemId).toList(),
        ),
      );
    }),
  );
  Future<StudySubject> createSubject({
    required String name,
    String teacher = '',
  }) => _run(() async {
    final s = StudySubject(
      id: _uuid.v4(),
      name: name.trim(),
      teacher: teacher.trim(),
    );
    await _mutate(() async {
      await _saveSubject(s);
      subjects = [...subjects, s];
    });
    return s;
  });
  Future<void> _saveSubject(StudySubject s) async {
    if (s.name.trim().isEmpty) {
      throw ArgumentError('Укажите название предмета.');
    }
    if (!isDemo) {
      await _cloud(
        () => _client!.from('student_subjects').upsert({
          'id': s.id,
          'user_id': _uid,
          'data': s.toJson(),
        }),
      );
    }
  }

  Future<void> updateSubject(StudySubject s) => _run(
    () => _mutate(() async {
      if (subjectById(s.id) == null) throw ArgumentError('Предмет не найден.');
      await _saveSubject(s);
      subjects = subjects.map((v) => v.id == s.id ? s : v).toList();
    }),
  );
  Future<void> deleteSubject(String id) => _run(
    () => _mutate(() async {
      if (classes.any((c) => c.subjectId == id) ||
          assignments.any((a) => a.subjectId == id)) {
        throw ArgumentError(
          'Сначала перенесите задания и удалите пары этого предмета.',
        );
      }
      if (!isDemo) {
        await _cloud(
          () => _client!.from('student_subjects').delete().eq('id', id),
        );
      }
      subjects = subjects.where((s) => s.id != id).toList();
    }),
  );
  Future<StudyClass> createClass({
    required String subjectId,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String room = '',
    String teacher = '',
  }) => _run(() async {
    final c = StudyClass(
      id: _uuid.v4(),
      subjectId: subjectId,
      title: title.trim(),
      startsAt: startsAt,
      endsAt: endsAt,
      room: room.trim(),
      teacher: teacher.trim(),
    );
    await _mutate(() async {
      await _saveClass(c);
      classes = [...classes, c];
    });
    return c;
  });
  Future<void> _saveClass(StudyClass c) async {
    _validateClass(c);
    if (!isDemo) {
      await _cloud(
        () => _client!.from('student_classes').upsert({
          'id': c.id,
          'user_id': _uid,
          'subject_id': c.subjectId,
          'data': c.toJson(),
        }),
      );
    }
  }

  Future<void> updateClass(StudyClass c) => _run(
    () => _mutate(() async {
      if (classById(c.id) == null) throw ArgumentError('Пара не найдена.');
      if (assignments.any(
        (a) => a.classId == c.id && a.subjectId != c.subjectId,
      )) {
        throw ArgumentError(
          'Пара связана с заданием другого предмета. Сначала измените контекст задания.',
        );
      }
      await _saveClass(c);
      classes = classes.map((v) => v.id == c.id ? c : v).toList();
    }),
  );
  Future<void> deleteClass(String id) => _run(
    () => _mutate(() async {
      // Cloud FK intentionally RESTRICTs linked classes; clear references first.
      if (!isDemo && assignments.any((a) => a.classId == id)) {
        throw ArgumentError('Сначала уберите связь с парой в заданиях.');
      }
      if (!isDemo) {
        await _cloud(
          () => _client!.from('student_classes').delete().eq('id', id),
        );
      }
      assignments = assignments
          .map((a) => a.classId == id ? a.copyWith(classId: null) : a)
          .toList();
      classes = classes.where((c) => c.id != id).toList();
    }),
  );
  Future<void> updateProfile(StudyProfile value) =>
      _run(() => _mutate(() => _saveProfile(value)));
  Future<void> _saveProfile(StudyProfile value) async {
    if (value.name.trim().isEmpty ||
        value.course < 1 ||
        value.course > 8 ||
        value.subgroup < 1 ||
        value.subgroup > 20) {
      throw ArgumentError('Проверьте имя, курс и подгруппу.');
    }
    if (!isDemo) {
      await _cloud(
        () => _client!.from('student_profiles').upsert({
          'id': _uid,
          'data': value.toJson(),
        }),
      );
    }
    profile = value;
  }

  String get _uid => _client!.auth.currentUser!.id;
  Future<T> _cloud<T>(Future<T> Function() request) async {
    final revision = _revision;
    final uid = _client?.auth.currentUser?.id;
    if (!authenticated || isDemo || uid == null) {
      throw StateError('Войдите в аккаунт.');
    }
    final result = await request();
    if (revision != _revision ||
        isDemo ||
        !authenticated ||
        uid != _client?.auth.currentUser?.id) {
      throw StateError('Сессия изменилась. Войдите снова.');
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _readRows(String table) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await _cloud(
        () => _client!
            .from(table)
            .select()
            .order('id')
            .range(offset, offset + 499),
      );
      result.addAll(rows);
      if (rows.length < 500) return result;
    }
  }

  Future<void> _loadCloud() async {
    final s = await _readRows('student_subjects');
    final c = await _readRows('student_classes');
    final a = await _readRows('student_assignments');
    final p = await _cloud(
      () => _client!
          .from('student_profiles')
          .select()
          .eq('id', _uid)
          .maybeSingle(),
    );
    subjects = s
        .map(
          (v) => StudySubject.fromJson(
            Map<String, dynamic>.from(v['data'])..['id'] = v['id'],
          ),
        )
        .toList();
    classes = c
        .map(
          (v) => StudyClass.fromJson(
            Map<String, dynamic>.from(v['data'])
              ..['id'] = v['id']
              ..['subjectId'] = v['subject_id'],
          ),
        )
        .toList();
    assignments = a
        .map(
          (v) => StudyAssignment.fromJson(
            Map<String, dynamic>.from(v['data'])
              ..['id'] = v['id']
              ..['subjectId'] = v['subject_id']
              ..['classId'] = v['class_id'],
          ),
        )
        .toList();
    profile = p == null
        ? StudyProfile(
            name: _client!.auth.currentUser?.userMetadata?['name'] ?? '',
            email: _client.auth.currentUser?.email ?? '',
          )
        : StudyProfile.fromJson(Map<String, dynamic>.from(p['data']));
  }

  Future<StudyAssignment> _saveCloudAssignment(StudyAssignment a) async {
    final uploaded = <String>[];
    final prepared = <StudyMaterial>[];
    var committed = false;
    try {
      for (final m in a.materials) {
        if (m.bytes != null) {
          final path = '$_uid/${a.id}/${_uuid.v4()}';
          await _cloud(
            () => _client!.storage
                .from(materialBucket)
                .uploadBinary(
                  path,
                  m.bytes!,
                  fileOptions: FileOptions(
                    contentType: m.mimeType ?? 'application/octet-stream',
                  ),
                ),
          );
          uploaded.add(path);
          prepared.add(
            m.copyWith(bytes: null, storagePath: path, byteLength: m.size),
          );
        } else {
          prepared.add(m);
        }
      }
      final saved = a.copyWith(materials: prepared);
      await _cloud(
        () => _client!.from('student_assignments').upsert({
          'id': saved.id,
          'user_id': _uid,
          'subject_id': saved.subjectId,
          'class_id': saved.classId,
          'data': saved.toJson(includeBytes: false),
        }),
      );
      committed = true;
      final removed = (assignmentById(a.id)?.materials ?? [])
          .where(
            (m) =>
                m.storagePath != null &&
                !prepared.any((n) => n.storagePath == m.storagePath),
          )
          .toList();
      await _cleanupFiles(removed);
      return saved;
    } catch (_) {
      if (!committed && uploaded.isNotEmpty) {
        try {
          await _client!.storage.from(materialBucket).remove(uploaded);
        } catch (_) {
          /* Own orphan can be retried/cleaned later. */
        }
      }
      rethrow;
    }
  }

  Future<void> _cleanupFiles(List<StudyMaterial> materials) async {
    final uid = _client?.auth.currentUser?.id;
    if (uid == null || isDemo) return;
    final paths = materials
        .map((m) => m.storagePath)
        .whereType<String>()
        .where((p) => p.startsWith('$uid/'))
        .toList();
    if (paths.isEmpty) return;
    try {
      await _cloud(() => _client!.storage.from(materialBucket).remove(paths));
    } catch (_) {
      /* DB remains authoritative; an orphan is safer than lost context. */
    }
  }

  Future<Uint8List> loadMaterialBytes(StudyMaterial material) async {
    if (material.bytes != null) return material.bytes!;
    if (isDemo ||
        material.storagePath == null ||
        !material.storagePath!.startsWith('$_uid/')) {
      throw StateError('Файл недоступен.');
    }
    return _cloud(
      () =>
          _client!.storage.from(materialBucket).download(material.storagePath!),
    );
  }

  Future<Uint8List> readMaterial(StudyMaterial material) =>
      loadMaterialBytes(material);
  Future<Uint8List> readMaterialBytes(StudyMaterial material) =>
      loadMaterialBytes(material);

  Future<String> materialUrl(StudyMaterial material) async {
    if (material.url != null) return material.url!;
    if (isDemo ||
        material.storagePath == null ||
        !material.storagePath!.startsWith('$_uid/')) {
      throw StateError('У локального файла нет публичной ссылки.');
    }
    return _cloud(
      () => _client!.storage
          .from(materialBucket)
          .createSignedUrl(material.storagePath!, 300),
    );
  }

  void _seed() {
    // Dates follow the current local day, so a live demo never opens an expired term.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    profile = const StudyProfile(
      name: 'Аня Смирнова',
      email: 'anya@example.test',
      group: 'ИС-21',
      course: 2,
      subgroup: 1,
    );
    subjects = const [
      StudySubject(id: 'math', name: 'Математика', teacher: 'Ирина Петрова'),
      StudySubject(
        id: 'informatics',
        name: 'Информатика',
        teacher: 'Алексей Волков',
        color: 0xff4c6b9b,
      ),
      StudySubject(
        id: 'history',
        name: 'История',
        teacher: 'Ольга Соколова',
        color: 0xff9a6518,
      ),
    ];
    classes = [
      for (var day = 0; day < 7; day++) ...[
        StudyClass(
          id: 'math-$day',
          subjectId: 'math',
          title: 'Практика',
          startsAt: today.add(Duration(days: day, hours: 9)),
          endsAt: today.add(Duration(days: day, hours: 10, minutes: 30)),
          room: '304 · корпус А',
          teacher: 'Ирина Петрова',
        ),
        StudyClass(
          id: 'history-$day',
          subjectId: 'history',
          title: 'Лекция',
          startsAt: today.add(Duration(days: day, hours: 10, minutes: 45)),
          endsAt: today.add(Duration(days: day, hours: 12, minutes: 15)),
          room: '201 · корпус Б',
          teacher: 'Ольга Соколова',
        ),
      ],
    ];
    assignments = [
      StudyAssignment(
        id: 'derivatives',
        subjectId: 'math',
        classId: 'math-0',
        title: 'Производные · задачи 1–8',
        description: 'Решить задачи 1–8 из практикума. Показать ход решения и проверить ответы.',
        dueAt: today.add(const Duration(days: 1, hours: 18)),
        status: StudyStatus.inProgress,
        checklist: const [
          StudyChecklistItem(
            id: 'read',
            title: 'Повторить правила',
            done: true,
          ),
          StudyChecklistItem(id: 'solve', title: 'Решить задачи'),
          StudyChecklistItem(id: 'check', title: 'Проверить ответы'),
        ],
        materials: const [
          StudyMaterial(
            id: 'math-reference',
            name: 'Правила дифференцирования',
            url: 'https://ru.wikibooks.org/wiki/Математический_анализ',
          ),
        ],
      ),
      StudyAssignment(
        id: 'lab2',
        subjectId: 'informatics',
        title: 'Лабораторная работа №2',
        description: 'Таблица, диаграмма и PDF-отчёт.',
        dueAt: today.add(const Duration(days: 3, hours: 18)),
      ),
      StudyAssignment(
        id: 'essay',
        subjectId: 'history',
        title: 'Эссе по теме семинара',
        dueAt: today.add(const Duration(days: 4, hours: 20)),
      ),
      StudyAssignment(
        id: 'limits',
        subjectId: 'math',
        title: 'Пределы · подготовка к практике',
        dueAt: today.add(const Duration(days: 2, hours: 18)),
        status: StudyStatus.inProgress,
      ),
      StudyAssignment(
        id: 'history-done',
        subjectId: 'history',
        title: 'Конспект лекции',
        dueAt: today.add(const Duration(hours: 18)),
        status: StudyStatus.done,
        completedAt: today,
        reminderMinutes: null,
      ),
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    _auth?.cancel();
    super.dispose();
  }
}
