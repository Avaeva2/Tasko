import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'task_query.dart';

class TaskView {
  final String id, name;
  final TaskQuery query;
  const TaskView({required this.id, required this.name, required this.query});
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'query': query.toJson(),
  };
}

/// Device preferences scoped to demo or the authenticated UUID, never email.
class TaskViews {
  final String scope;
  static final Map<String, Future<void>> _pending = {};
  const TaskViews(this.scope);
  String get storageKey => 'tasko.views.v1.$scope';
  Future<List<TaskView>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return [];
    final result = <TaskView>[];
    try {
      final rows = jsonDecode(raw) as List;
      for (final row in rows.take(10)) {
        try {
          final map = Map<String, dynamic>.from(row as Map);
          final id = map['id'] as String;
          final name = map['name'] as String;
          if (id.isEmpty ||
              id.length > 100 ||
              name.trim().isEmpty ||
              name.length > 40 ||
              result.any(
                (v) =>
                    v.id == id ||
                    normalizeTaskSearch(v.name) == normalizeTaskSearch(name),
              )) {
            continue;
          }
          result.add(
            TaskView(
              id: id,
              name: name,
              query: TaskQuery.fromJson(
                Map<String, dynamic>.from(map['query'] as Map),
              ),
            ),
          );
        } catch (_) {
          // An invalid entry does not destroy the other views or demo data.
        }
      }
    } catch (_) {
      return [];
    }
    return result;
  }

  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = (_pending[storageKey] ?? Future<void>.value()).then(
      (_) => action(),
    );
    final barrier = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending[storageKey] = barrier;
    barrier.then((_) {
      if (identical(_pending[storageKey], barrier)) {
        _pending.remove(storageKey);
      }
    });
    return result;
  }

  Future<List<TaskView>> save(String name, TaskQuery query) =>
      _mutate(() async {
        final normalized = name.trim();
        if (normalized.isEmpty || normalized.length > 40) {
          throw ArgumentError('Название: от 1 до 40 символов.');
        }
        // Reject a snapshot that load() would discard after a restart.
        try {
          TaskQuery.fromJson(query.toJson());
        } on FormatException {
          throw ArgumentError('Некорректные условия представления.');
        }
        final views = await load();
        if (views.any(
          (v) => normalizeTaskSearch(v.name) == normalizeTaskSearch(normalized),
        )) {
          throw ArgumentError('Представление с таким названием уже есть.');
        }
        if (views.length >= 10) {
          throw ArgumentError('Можно сохранить до 10 представлений.');
        }
        final updated = [
          ...views,
          TaskView(id: const Uuid().v4(), name: normalized, query: query),
        ];
        await _write(updated);
        return updated;
      });

  Future<List<TaskView>> delete(String id) => _mutate(() async {
    final updated = (await load()).where((v) => v.id != id).toList();
    await _write(updated);
    return updated;
  });

  Future<void> _write(List<TaskView> views) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      storageKey,
      jsonEncode(views.map((v) => v.toJson()).toList()),
    )) {
      throw StateError('Не удалось сохранить представление.');
    }
  }
}
