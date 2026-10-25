import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasko/student/student_assignment_screens.dart';
import 'package:tasko/student/student_models.dart';
import 'package:tasko/student/student_store.dart';
import 'package:tasko/student/student_theme.dart';

class _FilePicker extends FilePicker {
  final bytes = Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 55]);
  int picks = 0;
  Uint8List? saved;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    picks++;
    expect(withData, isTrue);
    return FilePickerResult([
      PlatformFile(name: 'Условие.pdf', size: bytes.length, bytes: bytes),
    ]);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saved = bytes;
    return '/example/$fileName';
  }
}

class _FailingStudentStore extends StudentStore {
  _FailingStudentStore() : super(persistDemo: false);
  bool failNextSave = true;
  @override
  Future<void> updateContext(
    String id, {
    required String description,
    required String subjectId,
    String? classId,
    required List<StudyMaterial> materials,
  }) async {
    if (failNextSave) {
      throw StateError('Не удалось сохранить. Повторите попытку.');
    }
    return super.updateContext(
      id,
      description: description,
      subjectId: subjectId,
      classId: classId,
      materials: materials,
    );
  }
}

Future<StudentStore> _store() async {
  final store = StudentStore(persistDemo: false);
  await store.enterDemo();
  return store;
}

Future<void> _app(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: StudentTheme.light, home: child));
  await tester.pumpAndSettle();
}

Future<void> _reach(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  test('material links require an HTTP(S) host and preserve valid paths', () {
    expect(
      validateStudyMaterialUrl('https://university.example/course?q=1'),
      isNull,
    );
    expect(validateStudyMaterialUrl('http://localhost:8080/task'), isNull);
    for (final invalid in [
      '',
      'javascript:alert(1)',
      'file:///tmp/report.pdf',
      'https://',
      'https://bad host/a',
    ]) {
      expect(validateStudyMaterialUrl(invalid), isNotNull, reason: invalid);
    }
  });

  testWidgets(
    'link validation keeps entered data and never adds an invalid material',
    (tester) async {
      await _app(tester, const StudyLinkEditor());
      await tester.enterText(
        find.byKey(const ValueKey('material-name-input')),
        'Условие',
      );
      await tester.enterText(
        find.byKey(const ValueKey('material-url-input')),
        'javascript:alert(1)',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Добавить ссылку'));
      await tester.pumpAndSettle();
      expect(
        find.text('Укажите корректную ссылку с http:// или https://'),
        findsOneWidget,
      );
      expect(find.text('Условие'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'context files stay in the draft and cancel leaves assignment unchanged',
    (tester) async {
      final store = await _store();
      addTearDown(store.dispose);
      final original = store.assignments.first;
      final picker = _FilePicker();
      FilePicker.platform = picker;
      await _app(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => StudyAssignmentEditor(
                    store: store,
                    assignment: original,
                    contextOnly: true,
                  ),
                ),
              ),
              child: const Text('Открыть редактор'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть редактор'));
      await tester.pumpAndSettle();
      await _reach(
        tester,
        find.byKey(const ValueKey('assignment-description-input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('assignment-description-input')),
        'Черновик нового условия',
      );
      await _reach(tester, find.byKey(const ValueKey('add-assignment-file')));
      await tester.tap(find.byKey(const ValueKey('add-assignment-file')));
      await tester.pumpAndSettle();
      expect(picker.picks, 1);
      expect(
        store.assignmentById(original.id)!.description,
        original.description,
      );
      expect(
        store.assignmentById(original.id)!.materials.length,
        original.materials.length,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Не сохранять'));
      await tester.pumpAndSettle();
      expect(find.text('Открыть редактор'), findsOneWidget);
      expect(
        store.assignmentById(original.id)!.description,
        original.description,
      );
      expect(
        store.assignmentById(original.id)!.materials.length,
        original.materials.length,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving context commits real picked bytes and subject change clears incompatible class',
    (tester) async {
      final store = await _store();
      addTearDown(store.dispose);
      final original = store.assignments.first;
      final linked = store.classes.firstWhere(
        (item) => item.subjectId == original.subjectId,
      );
      await store.updateContext(
        original.id,
        description: original.description,
        subjectId: original.subjectId,
        classId: linked.id,
        materials: original.materials,
      );
      final before = store.assignmentById(original.id)!;
      final other = store.subjects.firstWhere(
        (item) => item.id != before.subjectId,
      );
      final picker = _FilePicker();
      FilePicker.platform = picker;
      await _app(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => StudyAssignmentEditor(
                    store: store,
                    assignment: before,
                    contextOnly: true,
                  ),
                ),
              ),
              child: const Text('Открыть редактор'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть редактор'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('subject-${before.subjectId}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(other.name).last);
      await tester.pumpAndSettle();
      await _reach(
        tester,
        find.byKey(const ValueKey('assignment-description-input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('assignment-description-input')),
        'Сохранённое условие',
      );
      await _reach(tester, find.byKey(const ValueKey('add-assignment-file')));
      await tester.tap(find.byKey(const ValueKey('add-assignment-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить контекст'));
      await tester.pumpAndSettle();
      final saved = store.assignmentById(original.id)!;
      expect(saved.subjectId, other.id);
      expect(saved.classId, isNull);
      expect(saved.description, 'Сохранённое условие');
      expect(saved.materials.last.name, 'Условие.pdf');
      expect(saved.materials.last.bytes, orderedEquals(picker.bytes));
      expect(find.text('Открыть редактор'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detail checklist and complete/reopen mutate the shared assignment',
    (tester) async {
      final store = await _store();
      addTearDown(store.dispose);
      final task = store.assignments.firstWhere(
        (item) => item.checklist.isNotEmpty,
      );
      final item = task.checklist.last;
      await _app(
        tester,
        StudyAssignmentScreen(store: store, assignmentId: task.id),
      );
      await _reach(tester, find.byKey(ValueKey('checklist-${item.id}')));
      await tester.tap(find.byKey(ValueKey('checklist-${item.id}')));
      await tester.pumpAndSettle();
      expect(store.assignmentById(task.id)!.checklist.last.done, !item.done);
      await tester.tap(find.widgetWithText(FilledButton, 'Завершить задание'));
      await tester.pumpAndSettle();
      expect(store.assignmentById(task.id)!.status, StudyStatus.done);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Вернуть в работу'));
      await tester.pumpAndSettle();
      expect(store.assignmentById(task.id)!.status, StudyStatus.inProgress);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty assignment title blocks creation at the input', (
    tester,
  ) async {
    final store = await _store();
    addTearDown(store.dispose);
    final count = store.assignments.length;
    await _app(tester, StudyAssignmentEditor(store: store));
    await tester.tap(find.widgetWithText(FilledButton, 'Добавить задание'));
    await tester.pumpAndSettle();
    expect(find.text('Введите название задания'), findsOneWidget);
    expect(store.assignments.length, count);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save keeps the draft and retry commits it once', (
    tester,
  ) async {
    final store = _FailingStudentStore();
    await store.enterDemo();
    addTearDown(store.dispose);
    final original = store.assignments.first;
    await _app(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => StudyAssignmentEditor(
                  store: store,
                  assignment: original,
                  contextOnly: true,
                ),
              ),
            ),
            child: const Text('Открыть редактор'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть редактор'));
    await tester.pumpAndSettle();
    await _reach(
      tester,
      find.byKey(const ValueKey('assignment-description-input')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('assignment-description-input')),
      'Черновик не потеряется',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить контекст'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось сохранить. Повторите попытку.'), findsWidgets);
    expect(
      store.assignmentById(original.id)!.description,
      original.description,
    );
    expect(find.text('Черновик не потеряется'), findsOneWidget);
    store.failNextSave = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить контекст'));
    await tester.pumpAndSettle();
    expect(
      store.assignmentById(original.id)!.description,
      'Черновик не потеряется',
    );
    expect(find.text('Открыть редактор'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
