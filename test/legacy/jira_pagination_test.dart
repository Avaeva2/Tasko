import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/models.dart';

const _userId = '11111111-1111-1111-1111-111111111111';
const _created = '2026-10-07T09:00:00Z';

Future<SupabaseClient> _client(http.Client transport) async {
  final client = SupabaseClient(
    'http://pagination.test',
    'sb_publishable_test',
    httpClient: transport,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final expiration =
      DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
      1000;
  final token =
      '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': _userId, 'exp': expiration})))}.test';
  await client.auth.setInitialSession(
    jsonEncode({
      'access_token': token,
      'refresh_token': 'test-refresh',
      'token_type': 'bearer',
      'expires_in': 7200,
      'user': {
        'id': _userId,
        'email': 'pagination@example.test',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': _created,
      },
    }),
  );
  return client;
}

Map<String, dynamic> _task(int index) => {
  'id': 'task-${index.toString().padLeft(4, '0')}',
  'project_id': 'project-0000',
  'title': 'Task $index',
  'description': '',
  'status': 'todo',
  'priority': 'medium',
  'created_at': _created,
  'labels': <String>[],
  'issue_type': 'task',
  'issue_number': index + 1,
  'position': index + 1,
};

Map<String, List<Map<String, dynamic>>> _tables() => {
  'projects': List.generate(
    1001,
    (index) => {
      'id': 'project-${index.toString().padLeft(4, '0')}',
      'name': 'Project $index',
      'key': 'P$index',
      'description': '',
      'created_at': _created,
    },
  ),
  'tasks': List.generate(1001, _task),
  'profiles': [
    {'id': _userId, 'name': 'Pagination', 'role': ''},
  ],
  'task_subtasks': List.generate(
    1001,
    (index) => {
      'id': 'sub-${index.toString().padLeft(4, '0')}',
      'task_id': 'task-0000',
      'title': 'Child $index',
      'done': false,
      'created_at': _created,
    },
  ),
  'task_comments': List.generate(
    1001,
    (index) => {
      'id': 'comment-${index.toString().padLeft(4, '0')}',
      'task_id': 'task-0000',
      'author_name': 'Pagination',
      'body': 'Comment $index',
      'created_at': _created,
    },
  ),
  'task_activities': List.generate(
    1001,
    (index) => {
      'id': 'activity-${index.toString().padLeft(4, '0')}',
      'task_id': 'task-0000',
      'actor_name': 'Pagination',
      'body': 'Event $index',
      'created_at': _created,
    },
  ),
};

http.Response _json(
  Object value, {
  int status = 200,
  http.BaseRequest? request,
}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
  request: request,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real Supabase SDK loads 1000+1 projects/tasks/details via stable pages and keeps full JSON move snapshot', () async {
    final tables = _tables();
    final offsets = <String, List<int>>{};
    final requests = <(String, Map<String, String>, bool)>[];
    final client = await _client(
      MockClient((request) async {
        if (request.url.path.endsWith('/rpc/move_task')) {
          final params = jsonDecode(request.body) as Map;
          return _json(
            tables['tasks']!
                .map(
                  (task) => task['id'] == params['p_task_id']
                      ? {...task, 'status': params['p_status']}
                      : task,
                )
                .toList(),
            request: request,
          );
        }
        final table = request.url.pathSegments.last;
        final query = request.url.queryParameters;
        requests.add((
          table,
          query,
          (request.headers['authorization'] ??
                  request.headers['Authorization'] ??
                  '')
              .startsWith('Bearer '),
        ));
        final offset = int.parse(query['offset'] ?? '0');
        // This fake server obeys the actual max_rows=1000 cap even without limit.
        final requested = int.parse(query['limit'] ?? '1000');
        final limit = requested > 1000 ? 1000 : requested;
        offsets.putIfAbsent(table, () => []).add(offset);
        return _json(
          tables[table]!.skip(offset).take(limit).toList(),
          request: request,
        );
      }),
    );
    final store = TaskoStore(client: client, persistDemo: false);
    addTearDown(() async {
      store.dispose();
      await client.dispose();
    });
    await store.initialize();
    expect(
      store.error,
      isNull,
      reason: requests
          .map((request) => '${request.$1}:${request.$2}')
          .join(';'),
    );
    expect(store.projects, hasLength(1001));
    expect(store.tasks, hasLength(1001));
    await store.loadTaskDetails('task-0000');
    expect(store.subtasks, hasLength(1001));
    expect(store.comments, hasLength(1001));
    expect(store.activities, hasLength(1001));
    for (final (table, query, authenticated) in requests) {
      expect(authenticated, isTrue);
      expect(
        query['order'],
        table == 'profiles'
            ? 'id.asc.nullslast'
            : 'created_at.asc.nullslast,id.asc.nullslast',
      );
      if (table.startsWith('task_')) expect(query['task_id'], 'eq.task-0000');
      if (table == 'profiles') expect(query['id'], 'eq.$_userId');
    }
    for (final table in [
      'projects',
      'tasks',
      'task_subtasks',
      'task_comments',
      'task_activities',
    ]) {
      expect(offsets[table], [
        0,
        500,
        1000,
      ], reason: 'The 1001st $table row must be fetched.');
    }
    await store.moveTask('task-0000', TaskStatus.review);
    expect(store.tasks, hasLength(1001));
    expect(store.tasks.map((task) => task.id).toSet(), hasLength(1001));
    expect(
      store.tasks.singleWhere((task) => task.id == 'task-0000').status,
      TaskStatus.review,
    );
    expect(store.tasks.any((task) => task.id == 'task-1000'), isTrue);
  });

  test(
    'sign-out during a later page discards the entire pending dataset',
    () async {
      final tables = _tables();
      late SupabaseClient client;
      var invalidated = false;
      client = await _client(
        MockClient((request) async {
          if (request.url.path.endsWith('/logout')) {
            return http.Response('', 204, request: request);
          }
          final table = request.url.pathSegments.last;
          final query = request.url.queryParameters;
          final offset = int.parse(query['offset'] ?? '0');
          if (table == 'tasks' && offset == 500 && !invalidated) {
            invalidated = true;
            await client.auth.signOut();
          }
          return _json(
            tables[table]!
                .skip(offset)
                .take(int.parse(query['limit'] ?? '1000'))
                .toList(),
            request: request,
          );
        }),
      );
      final store = TaskoStore(client: client, persistDemo: false);
      addTearDown(() async {
        store.dispose();
        await client.dispose();
      });
      await store.initialize();
      expect(invalidated, isTrue);
      expect(store.isAuthenticated, isFalse);
      expect(store.projects, isEmpty);
      expect(store.tasks, isEmpty);
      expect(store.error, contains('Сессия изменилась'));
    },
  );
}
