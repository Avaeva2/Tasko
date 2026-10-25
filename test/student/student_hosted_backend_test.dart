import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tasko/student/student_models.dart';
import 'package:tasko/student/student_store.dart';

/// Explicit deployment check. Uses only the four Tasko mock accounts.
/// Credentials and privileged backend keys are never embedded in this file.
void main() {
  test(
    'hosted HTTPS Auth fixtures CRUD RLS and private file roundtrip',
    () async {
      final config = jsonDecode(
        File('config/student-hosted.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final url = config['SUPABASE_URL'] as String;
      expect(Uri.parse(url).scheme, 'https');
      final users = (jsonDecode(
        File('config/student-hosted-test-users.json').readAsStringSync(),
      ) as List).cast<Map<String, dynamic>>();
      const options = AuthClientOptions(authFlowType: AuthFlowType.implicit);
      final clients = <SupabaseClient>[];
      final stores = <StudentStore>[];
      addTearDown(() async {
        for (final store in stores) {
          store.dispose();
        }
        for (final client in clients) {
          await client.dispose();
        }
      });
      final observed = <Map<String, dynamic>>[];
      for (final user in users) {
        final client = SupabaseClient(
          url,
          config['SUPABASE_ANON_KEY'],
          authOptions: options,
        );
        final store = StudentStore(client: client, persistDemo: false);
        clients.add(client);
        stores.add(store);
        await store.initialize();
        await store.login(user['login'], user['password']);
        expect(store.authenticated, isTrue);
        expect(store.isDemo, isFalse);
        expect(store.profile.email, user['login']);
        expect(store.subjects.length, user['subjects']);
        expect(store.classes.length, user['classes']);
        expect(store.assignments.length, user['assignments']);
        observed.add({
          'login': user['login'],
          'subjects': store.subjects.length,
          'classes': store.classes.length,
          'assignments': store.assignments.length,
        });
      }
      final seeded = stores.first.assignments
          .expand((a) => a.materials)
          .firstWhere((m) => m.storagePath != null);
      final seededBytes = await stores.first.readMaterial(seeded);
      expect(seededBytes.length, seeded.size);
      expect(
        utf8.decode(seededBytes),
        contains('Учебный пример Tasko Students'),
      );

      final a = stores.last, b = stores.first;
      final clientA = clients.last, clientB = clients.first;
      final uidA = clientA.auth.currentUser!.id;
      String? subjectId, classId, assignmentId;
      final payload = Uint8List.fromList(
        utf8.encode('Tasko hosted roundtrip\nActual private file bytes.\n'),
      );
      try {
        final subject = await a.createSubject(
          name: 'QA hosted temporary',
          teacher: 'Тест',
        );
        subjectId = subject.id;
        final start = DateTime.now().add(const Duration(days: 2));
        final lesson = await a.createClass(
          subjectId: subject.id,
          title: 'QA практика',
          startsAt: start,
          endsAt: start.add(const Duration(minutes: 90)),
          room: 'QA',
        );
        classId = lesson.id;
        final assignment = await a.createAssignment(
          title: 'QA hosted temporary assignment',
          subjectId: subject.id,
          classId: lesson.id,
          dueAt: start.add(const Duration(days: 1)),
          description: 'Проверка реального HTTPS backend',
          checklist: const [
            StudyChecklistItem(id: 'qa-check', title: 'Проверить сохранение'),
          ],
          materials: [
            StudyMaterial(
              id: 'qa-file',
              name: 'Проверка.txt',
              bytes: payload,
              mimeType: 'text/plain',
            ),
          ],
        );
        assignmentId = assignment.id;
        final file = assignment.materials.single;
        expect(await a.readMaterial(file), payload);
        final signed = await a.materialUrl(file);
        expect(Uri.parse(signed).host, Uri.parse(url).host);
        expect(Uri.parse(signed).scheme, 'https');
        expect((await http.get(Uri.parse(signed))).bodyBytes, payload);
        expect(
          (await http.get(
            Uri.parse(
              '$url/storage/v1/object/public/student-materials/${file.storagePath}',
            ),
          )).statusCode,
          isNot(200),
        );
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
          await clientB.from('student_profiles').select().eq('id', uidA),
          isEmpty,
        );
        await expectLater(
          clientB.from('student_subjects').insert({
            'user_id': uidA,
            'data': {'name': 'QA denied foreign insert'},
          }),
          throwsA(isA<PostgrestException>()),
        );
        await clientB
            .from('student_assignments')
            .update({
              'data': assignment.toJson(includeBytes: false)
                ..['title'] = 'QA forbidden change',
            })
            .eq('id', assignment.id);
        await a.toggleChecklist(assignment.id, 'qa-check', true);
        await a.setStatus(assignment.id, StudyStatus.done);
        await a.logout();
        await a.login(users.last['login'], users.last['password']);
        final loaded = a.assignmentById(assignment.id)!;
        expect(loaded.title, 'QA hosted temporary assignment');
        expect(loaded.description, 'Проверка реального HTTPS backend');
        expect(loaded.classId, lesson.id);
        expect(loaded.status, StudyStatus.done);
        expect(loaded.checklist.single.done, isTrue);
        expect(await a.readMaterial(loaded.materials.single), payload);
        await a.updateContext(
          assignment.id,
          description: 'QA link only',
          subjectId: subject.id,
          classId: lesson.id,
          materials: const [
            StudyMaterial(
              id: 'qa-link',
              name: 'Материал',
              url: 'https://example.org/tasko-qa',
            ),
          ],
        );
        await expectLater(
          clientA.storage
              .from(StudentStore.materialBucket)
              .download(file.storagePath!),
          throwsA(isA<StorageException>()),
        );
      } finally {
        if (assignmentId != null) await a.deleteAssignment(assignmentId);
        if (classId != null) await a.deleteClass(classId);
        if (subjectId != null) await a.deleteSubject(subjectId);
      }
      expect(a.subjects, isEmpty);
      expect(a.classes, isEmpty);
      expect(a.assignments, isEmpty);
      final preflightRequest =
          http.Request('OPTIONS', Uri.parse('$url/rest/v1/student_subjects'))
            ..headers.addAll({
              'Origin': 'http://127.0.0.1:49182',
              'Access-Control-Request-Method': 'GET',
              'Access-Control-Request-Headers':
                  'apikey,authorization,x-client-info,content-type',
            });
      final preflight = await preflightRequest.send();
      await preflight.stream.drain<void>();
      expect(preflight.statusCode, anyOf(200, 204));
      expect(
        preflight.headers['access-control-allow-origin'],
        anyOf('*', 'http://127.0.0.1:49182'),
      );
      Directory('artifacts').createSync();
      File('artifacts/tasko-hosted-sdk-verification.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'ok': true,
          'url': url,
          'users': observed,
          'seedFileDownloaded': true,
          'privateFileRoundtrip': true,
          'crossOwnerReadDenied': true,
          'crossOwnerInsertDenied': true,
          'logoutLoginPersistence': true,
          'temporaryRecordsCleaned': true,
          'browserCors': true,
          'verifiedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      expect(b.assignments.length, users.first['assignments']);
    },
    skip: Platform.environment['TASKO_HOSTED_TEST'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
