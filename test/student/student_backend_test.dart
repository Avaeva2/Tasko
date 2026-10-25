import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tasko/student/student_models.dart';
import 'package:tasko/student/student_store.dart';

/// Explicit opt-in: STUDENT_BACKEND_TEST=1 flutter test ...
/// Uses ONLY the isolated 55421 local instance and synthetic throwaway users.
void main() {
  test(
    'isolated Supabase Auth CRUD RLS private files and class constraints',
    () async {
      final config = jsonDecode(
        File('config/student-local.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final url = config['SUPABASE_URL'] as String;
      expect(Uri.parse(url).host, anyOf('127.0.0.1', 'localhost'));
      expect(Uri.parse(url).port, 55421);
      const options = AuthClientOptions(authFlowType: AuthFlowType.implicit);
      final clientA = SupabaseClient(
        url,
        config['SUPABASE_ANON_KEY'],
        authOptions: options,
      );
      final clientB = SupabaseClient(
        url,
        config['SUPABASE_ANON_KEY'],
        authOptions: options,
      );
      final a = StudentStore(client: clientA, persistDemo: false);
      final b = StudentStore(client: clientB, persistDemo: false);
      addTearDown(() async {
        a.dispose();
        b.dispose();
        await clientA.dispose();
        await clientB.dispose();
      });
      final unique = DateTime.now().microsecondsSinceEpoch;
      final emailA = 'student-test-a-$unique@example.test';
      final emailB = 'student-test-b-$unique@example.test';
      const password = 'Student-test-only-5842!';
      await a.initialize();
      await b.initialize();
      await a.signUp(emailA, password, 'Тест А');
      await b.signUp(emailB, password, 'Тест Б');
      expect(a.authenticated, isTrue);
      expect(a.isDemo, isFalse);
      final uidA = clientA.auth.currentUser!.id;
      final math = await a.createSubject(
        name: 'Математика тест',
        teacher: 'Тестовый преподаватель',
      );
      final cs = await a.createClass(
        subjectId: math.id,
        title: 'Практика',
        startsAt: DateTime(2026, 11, 25, 9),
        endsAt: DateTime(2026, 11, 25, 10, 30),
        room: '304',
      );
      final payload = Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 52, 10]);
      final assignment = await a.createAssignment(
        title: 'Проверка сохранения',
        subjectId: math.id,
        classId: cs.id,
        dueAt: DateTime(2026, 11, 27, 18),
        description: 'Полный контекст',
        materials: [
          StudyMaterial(
            id: 'pdf',
            name: 'sample.pdf',
            bytes: payload,
            mimeType: 'application/pdf',
          ),
        ],
        checklist: const [StudyChecklistItem(id: 'check', title: 'Проверить')],
      );
      final file = assignment.materials.single;
      expect(file.bytes, isNull);
      expect(file.size, payload.length);
      expect(file.storagePath, startsWith('$uidA/${assignment.id}/'));
      expect(await a.readMaterial(file), payload);
      final publicResponse = await http.get(
        Uri.parse(
          '$url/storage/v1/object/public/student-materials/${file.storagePath}',
        ),
      );
      expect(publicResponse.statusCode, isNot(200));
      final signed = await a.materialUrl(file);
      expect((await http.get(Uri.parse(signed))).bodyBytes, payload);
      await expectLater(
        clientB.storage
            .from(StudentStore.materialBucket)
            .download(file.storagePath!),
        throwsA(isA<StorageException>()),
      );
      expect(
        await clientB
            .from('student_assignments')
            .select()
            .eq('id', assignment.id),
        isEmpty,
      );
      expect(
        await clientB.from('student_subjects').select().eq('id', math.id),
        isEmpty,
      );
      expect(
        await clientB.from('student_profiles').select().eq('id', uidA),
        isEmpty,
      );
      final attack = assignment.toJson(includeBytes: false)
        ..['title'] = 'Не должно измениться';
      await clientB
          .from('student_assignments')
          .update({'data': attack})
          .eq('id', assignment.id);
      await expectLater(
        clientB.from('student_subjects').insert({
          'user_id': uidA,
          'data': {'name': 'Чужая запись'},
        }),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        clientB.storage
            .from(StudentStore.materialBucket)
            .uploadBinary('$uidA/attack/file', payload),
        throwsA(isA<StorageException>()),
      );
      final other = await a.createSubject(name: 'Другой предмет');
      await expectLater(
        clientA
            .from('student_assignments')
            .update({'subject_id': other.id})
            .eq('id', assignment.id),
        throwsA(isA<PostgrestException>()),
      );
      await a.toggleChecklist(assignment.id, 'check', true);
      await a.setStatus(assignment.id, StudyStatus.done);
      await a.updateProfile(
        a.profile.copyWith(group: 'ТСТ-21', course: 2, subgroup: 2),
      );
      await a.logout();
      await a.login(emailA, password);
      final loaded = a.assignmentById(assignment.id)!;
      expect(loaded.title, 'Проверка сохранения');
      expect(loaded.description, 'Полный контекст');
      expect(loaded.classId, cs.id);
      expect(loaded.status, StudyStatus.done);
      expect(loaded.checklist.single.done, isTrue);
      expect(loaded.completedAt, isNotNull);
      expect(a.profile.group, 'ТСТ-21');
      expect(await a.readMaterial(loaded.materials.single), payload);
      await a.setStatus(assignment.id, StudyStatus.inProgress);
      expect(
        a.assignmentById(assignment.id)!.reminderAt,
        DateTime(2026, 11, 26, 18),
      );
      await a.updateContext(
        assignment.id,
        description: 'Изменено',
        subjectId: other.id,
        classId: null,
        materials: const [
          StudyMaterial(
            id: 'url',
            name: 'Ссылка',
            url: 'https://example.test/material',
          ),
        ],
      );
      await expectLater(
        clientA.storage
            .from(StudentStore.materialBucket)
            .download(file.storagePath!),
        throwsA(isA<StorageException>()),
      );
      await a.deleteAssignment(assignment.id);
      await a.deleteClass(cs.id);
      await a.deleteSubject(math.id);
      await a.deleteSubject(other.id);
      expect(
        await clientA
            .from('student_assignments')
            .select()
            .eq('id', assignment.id),
        isEmpty,
      );
      await b.logout();
      await a.logout();
    },
    skip: Platform.environment['STUDENT_BACKEND_TEST'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
