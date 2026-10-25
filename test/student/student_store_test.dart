import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasko/student/student_models.dart';
import 'package:tasko/student/student_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'tasko.demo.v2': 'legacy-pm-must-stay',
    }),
  );
  Future<StudentStore> demo() async {
    final store = StudentStore();
    addTearDown(store.dispose);
    await store.initialize();
    await store.enterDemo();
    return store;
  }

  test('isolated student data reloads context bytes checklist reminder and profile without overwriting PM', () async {
    final store = await demo();
    final due = DateTime(2026, 11, 15, 18);
    final assignment = await store.createAssignment(
      title: 'Лабораторная',
      subjectId: 'math',
      dueAt: due,
      reminderMinutes: 1440,
      materials: [
        StudyMaterial(
          id: 'pdf',
          name: 'Отчёт.pdf',
          bytes: Uint8List.fromList([1, 2, 3, 255]),
          mimeType: 'application/pdf',
        ),
      ],
      checklist: const [StudyChecklistItem(id: 'first', title: 'Проверить')],
    );
    await store.updateContext(
      assignment.id,
      description: 'Условие задания',
      subjectId: 'math',
      classId: 'math-0',
      materials: [
        ...assignment.materials,
        const StudyMaterial(
          id: 'url',
          name: 'Материалы',
          url: 'https://example.test/material',
        ),
      ],
    );
    await store.toggleChecklist(assignment.id, 'first', true);
    await store.updateProfile(
      store.profile.copyWith(group: 'ИС-31', course: 3, subgroup: 2),
    );
    final reloaded = await demo();
    final saved = reloaded.assignmentById(assignment.id)!;
    expect(saved.description, 'Условие задания');
    expect(saved.classId, 'math-0');
    expect(saved.materials.first.bytes, [1, 2, 3, 255]);
    expect(saved.materials.last.url, 'https://example.test/material');
    expect(await reloaded.readMaterial(saved.materials.first), [1, 2, 3, 255]);
    expect(saved.checklist.single.done, isTrue);
    expect(saved.reminderAt, DateTime(2026, 11, 14, 18));
    expect(reloaded.profile.group, 'ИС-31');
    expect(reloaded.profile.course, 3);
    expect(reloaded.profile.subgroup, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tasko.demo.v2'), 'legacy-pm-must-stay');
    expect(jsonDecode(prefs.getString(StudentStore.demoKey)!)['version'], 1);
  });

  test('complete and reopen update one board membership and persist completion date', () async {
    final store = await demo();
    final beforeWork = store.countStatus(StudyStatus.inProgress);
    final beforeDone = store.countStatus(StudyStatus.done);
    await store.setStatus('derivatives', StudyStatus.done);
    expect(store.countStatus(StudyStatus.inProgress), beforeWork - 1);
    expect(store.countStatus(StudyStatus.done), beforeDone + 1);
    expect(store.assignmentById('derivatives')!.completedAt, isNotNull);
    expect(store.assignmentById('derivatives')!.reminderAt, isNull);
    final reloaded = await demo();
    expect(reloaded.assignmentById('derivatives')!.status, StudyStatus.done);
    await reloaded.setStatus('derivatives', StudyStatus.inProgress);
    expect(reloaded.countStatus(StudyStatus.inProgress), beforeWork);
    expect(reloaded.countStatus(StudyStatus.done), beforeDone);
    expect(reloaded.assignmentById('derivatives')!.completedAt, isNull);
    expect(reloaded.assignmentById('derivatives')!.reminderAt, isNotNull);
  });

  test(
    'invalid subject class relation fails atomically without changing context',
    () async {
      final store = await demo();
      final original = store.assignmentById('derivatives')!;
      await expectLater(
        store.updateContext(
          original.id,
          description: 'Не сохранять',
          subjectId: 'informatics',
          classId: 'math-0',
          materials: [],
        ),
        throwsStateError,
      );
      expect(store.assignmentById(original.id)!.toJson(), original.toJson());
      final second = await demo();
      expect(second.assignmentById(original.id)!.toJson(), original.toJson());
      await store.updateContext(
        original.id,
        description: 'Другой предмет',
        subjectId: 'informatics',
        classId: null,
        materials: [],
      );
      expect(store.assignmentById(original.id)!.classId, isNull);
    },
  );

  test(
    'bad URL and empty title never leave partially created assignments',
    () async {
      final store = await demo();
      final count = store.assignments.length;
      await expectLater(
        store.createAssignment(
          title: '  ',
          subjectId: 'math',
          dueAt: DateTime(2026, 12, 1),
        ),
        throwsStateError,
      );
      await expectLater(
        store.createAssignment(
          title: 'Задание',
          subjectId: 'math',
          dueAt: DateTime(2026, 12, 1),
          materials: const [
            StudyMaterial(
              id: 'bad',
              name: 'Ссылка',
              url: 'javascript:alert(1)',
            ),
          ],
        ),
        throwsStateError,
      );
      expect(store.assignments.length, count);
      expect((await demo()).assignments.length, count);
    },
  );

  test('2MB TOTAL attachment budget rejects excess and preserves existing saved files', () async {
    final store = await demo();
    final a = await store.createAssignment(
      title: 'Первый файл',
      subjectId: 'math',
      dueAt: DateTime(2026, 12, 1),
      materials: [
        StudyMaterial(id: 'a', name: 'a.bin', bytes: Uint8List(1500000)),
      ],
    );
    final count = store.assignments.length;
    await expectLater(
      store.createAssignment(
        title: 'Лишний файл',
        subjectId: 'math',
        dueAt: DateTime(2026, 12, 1),
        materials: [
          StudyMaterial(id: 'b', name: 'b.bin', bytes: Uint8List(700000)),
        ],
      ),
      throwsStateError,
    );
    expect(store.assignments.length, count);
    expect(store.assignmentById(a.id)!.materials.single.size, 1500000);
    final reloaded = await demo();
    expect(
      reloaded.assignmentById(a.id)!.materials.single.bytes!.length,
      1500000,
    );
  });

  test(
    'concurrent checklist changes serialize rather than lose one change',
    () async {
      final store = await demo();
      await Future.wait([
        store.toggleChecklist('derivatives', 'solve', true),
        store.toggleChecklist('derivatives', 'check', true),
      ]);
      expect(
        store
            .assignmentById('derivatives')!
            .checklist
            .every((item) => item.done),
        isTrue,
      );
      expect(
        (await demo())
            .assignmentById('derivatives')!
            .checklist
            .every((item) => item.done),
        isTrue,
      );
    },
  );

  test('class edit validates time, delete detaches local references, subject deletion is guarded', () async {
    final store = await demo();
    final c = store.classById('math-0')!;
    await expectLater(
      store.updateClass(c.copyWith(endsAt: c.startsAt)),
      throwsStateError,
    );
    await expectLater(store.deleteSubject('math'), throwsStateError);
    await store.updateClass(c.copyWith(room: '505'));
    expect(store.classById(c.id)!.room, '505');
    await store.deleteClass(c.id);
    expect(store.assignmentById('derivatives')!.classId, isNull);
    expect((await demo()).assignmentById('derivatives')!.classId, isNull);
  });

  test(
    'reminder follows changed deadline and explicit null disables it',
    () async {
      final store = await demo();
      final original = store.assignmentById('derivatives')!;
      final due = DateTime(2026, 11, 24, 16, 30);
      await store.updateAssignment(
        original.copyWith(dueAt: due, reminderMinutes: 60),
      );
      expect(
        store.assignmentById(original.id)!.reminderAt,
        DateTime(2026, 11, 24, 15, 30),
      );
      await store.updateAssignment(
        store.assignmentById(original.id)!.copyWith(reminderMinutes: null),
      );
      expect((await demo()).assignmentById(original.id)!.reminderAt, isNull);
    },
  );

  test(
    'logout clears current view, explicit demo reset preserves legacy PM data',
    () async {
      final store = await demo();
      await store.deleteAssignment('essay');
      await store.logout();
      expect(store.authenticated, isFalse);
      expect(store.assignments, isEmpty);
      await store.enterDemo();
      expect(store.assignmentById('essay'), isNull);
      await store.resetDemo();
      expect(store.assignmentById('essay'), isNotNull);
      expect(
        (await SharedPreferences.getInstance()).getString('tasko.demo.v2'),
        'legacy-pm-must-stay',
      );
    },
  );

  test('corrupted demo is not silently overwritten and cloud login cannot fake demo', () async {
    SharedPreferences.setMockInitialValues({
      StudentStore.demoKey: 'broken-json',
    });
    final store = StudentStore();
    addTearDown(store.dispose);
    await store.initialize();
    await expectLater(store.enterDemo(), throwsStateError);
    expect(store.authenticated, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getString(StudentStore.demoKey),
      'broken-json',
    );
    await expectLater(
      store.login('test@example.test', 'testtest'),
      throwsStateError,
    );
    expect(store.authenticated, isFalse);
    expect(store.isDemo, isFalse);
  });
}
