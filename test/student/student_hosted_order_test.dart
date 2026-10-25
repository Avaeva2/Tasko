import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tasko/student/student_board_order.dart';
import 'package:tasko/student/student_models.dart';
import 'package:tasko/student/student_store.dart';

/// Checks only fresh, temporary QA records. Existing tester edits are untouched.
void main() {
  test(
    'hosted board order and status survive an independent client reload',
    () async {
      final config = jsonDecode(
        File('config/student-hosted.json').readAsStringSync(),
      );
      final users = jsonDecode(
        File('config/student-hosted-test-users.json').readAsStringSync(),
      ) as List;
      final user = users.firstWhere((u) => u['login'] == 'empty@tasko.test');
      expect(Uri.parse(config['SUPABASE_URL']).scheme, 'https');
      const options = AuthClientOptions(authFlowType: AuthFlowType.implicit);
      final clients = List.generate(
        2,
        (_) => SupabaseClient(
          config['SUPABASE_URL'],
          config['SUPABASE_ANON_KEY'],
          authOptions: options,
        ),
      );
      final stores = clients
          .map((c) => StudentStore(client: c, persistDemo: false))
          .toList();
      addTearDown(() async {
        for (final store in stores) {
          store.dispose();
        }
        for (final client in clients) {
          await client.dispose();
        }
      });
      final a = stores.first, b = stores.last;
      await a.initialize();
      await a.login(user['login'], user['password']);
      final beforeIds = a.assignments.map((a) => a.id).toSet();
      String? subjectId;
      final created = <String>[];
      try {
        final subject = await a.createSubject(
          name: 'QA board ${DateTime.now().microsecondsSinceEpoch}',
        );
        subjectId = subject.id;
        final due = DateTime.now().add(const Duration(days: 5));
        final tasks = <StudyAssignment>[];
        for (var i = 0; i < 3; i++) {
          final task = await a.createAssignment(
            title: 'QA order $i',
            subjectId: subject.id,
            dueAt: due.add(Duration(hours: i)),
          );
          tasks.add(task);
          created.add(task.id);
        }
        await a.moveAssignment(
          tasks[2].id,
          StudyStatus.todo,
          beforeId: tasks[0].id,
        );
        await a.moveAssignment(tasks[1].id, StudyStatus.done);
        await b.initialize();
        await b.login(user['login'], user['password']);
        final reloaded =
            b.assignments.where((a) => a.subjectId == subject.id).toList()
              ..sort(compareStudyBoard);
        expect(
          b.assignmentById(tasks[2].id)!.boardOrder,
          a.assignmentById(tasks[2].id)!.boardOrder,
        );
        expect(reloaded.first.id, tasks[2].id);
        expect(b.assignmentById(tasks[1].id)!.status, StudyStatus.done);
        expect(b.assignmentById(tasks[1].id)!.completedAt, isNotNull);
        // Update context after movement must preserve manual order.
        final saved = b.assignmentById(tasks[2].id)!;
        await b.updateAssignment(
          saved.copyWith(description: 'QA context after move'),
        );
        final row = await clients.first
            .from('student_assignments')
            .select('data')
            .eq('id', saved.id)
            .single();
        expect(row['data']['boardOrder'], saved.boardOrder);
        expect(row['data']['description'], 'QA context after move');
        File('artifacts/student-hosted-order-verification.json')
            .writeAsStringSync(
              jsonEncode({
                'host': config['SUPABASE_URL'],
                'independentReload': true,
                'sameColumnOrder': true,
                'statusAndCompletion': true,
                'contextPreservesOrder': true,
                'verifiedAt': DateTime.now().toUtc().toIso8601String(),
              }),
            );
      } finally {
        for (final id in created.reversed) {
          await a.deleteAssignment(id);
        }
        if (subjectId != null) await a.deleteSubject(subjectId);
        final remaining = await clients.first
            .from('student_assignments')
            .select('id');
        expect(remaining.map((r) => r['id']).toSet(), beforeIds);
      }
    },
    skip: Platform.environment['TASKO_HOSTED_ORDER_TEST'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
