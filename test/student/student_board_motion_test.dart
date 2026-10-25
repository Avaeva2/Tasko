import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasko/student/student_app.dart';
import 'package:tasko/student/student_board_order.dart';
import 'package:tasko/student/student_models.dart';
import 'package:tasko/student/student_store.dart';

class ControlledStore extends StudentStore {
  ControlledStore() : super(persistDemo: false);
  Completer<void>? gate;
  bool fail = false;
  int moves = 0;
  @override
  Future<void> moveAssignment(
    String id,
    StudyStatus status, {
    String? afterId,
    String? beforeId,
    DateTime? completedAt,
  }) async {
    moves++;
    await gate?.future;
    if (fail) throw StateError('Synthetic network failure');
    await super.moveAssignment(
      id,
      status,
      afterId: afterId,
      beforeId: beforeId,
      completedAt: completedAt,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('dense ranks survive 2000 arbitrary insertions and JSON roundtrip', () {
    final keys = <String>[];
    final random = Random(47);
    for (var i = 0; i < 2000; i++) {
      final index = random.nextInt(keys.length + 1);
      final left = index == 0 ? null : keys[index - 1];
      final right = index == keys.length ? null : keys[index];
      final key = studyBoardBetween(left, right);
      if (left != null) expect(key.compareTo(left), greaterThan(0));
      if (right != null) expect(key.compareTo(right), lessThan(0));
      keys.insert(index, key);
    }
    var right = 'V';
    for (var i = 0; i < 200; i++) {
      final next = studyBoardBetween(null, right);
      expect(next.compareTo(right), lessThan(0));
      right = next;
    }
    final a = StudyAssignment(
      id: 'a',
      subjectId: 'math',
      title: 'A',
      dueAt: DateTime(2026, 11),
      boardOrder: keys[900],
    );
    expect(StudyAssignment.fromJson(a.toJson()).boardOrder, keys[900]);
    expect(
      StudyAssignment.fromJson({...a.toJson(), 'boardOrder': 'invalid_'})
          .boardOrder,
      isNull,
    );
    expect(() => studyBoardBetween('V', 'U'), throwsArgumentError);
  });
  test(
    'same-column order and cross-column completion survive demo reload',
    () async {
      final store = StudentStore();
      await store.initialize();
      await store.enterDemo();
      final tasks =
          store.assignments.where((a) => a.status == StudyStatus.todo).toList()
            ..sort(compareStudyBoard);
      await store.moveAssignment(
        tasks.last.id,
        StudyStatus.todo,
        beforeId: tasks.first.id,
      );
      final saved = store.assignmentById(tasks.last.id)!;
      expect(compareStudyBoard(saved, tasks.first), lessThan(0));
      await store.moveAssignment(tasks.first.id, StudyStatus.done);
      expect(store.assignmentById(tasks.first.id)!.completedAt, isNotNull);
      final restored = StudentStore();
      await restored.initialize();
      await restored.enterDemo();
      expect(restored.assignmentById(saved.id)!.boardOrder, saved.boardOrder);
      expect(restored.assignmentById(tasks.first.id)!.status, StudyStatus.done);
      final original = restored.assignmentById(saved.id)!.toJson();
      await expectLater(
        restored.moveAssignment(
          saved.id,
          StudyStatus.todo,
          beforeId: 'missing',
        ),
        throwsStateError,
      );
      expect(restored.assignmentById(saved.id)!.toJson(), original);
      store.dispose();
      restored.dispose();
    },
  );
  Future<ControlledStore> boot(
    WidgetTester tester, {
    double width = 1020,
    bool reduced = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = ControlledStore();
    await store.initialize();
    await store.enterDemo();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          disableAnimations: reduced,
          textScaler: TextScaler.linear(scale),
        ),
        child: StudentApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    final nav = width >= 1000
        ? find.byType(NavigationRail)
        : find.byType(NavigationBar);
    await tester.tap(find.descendant(of: nav, matching: find.text('Задания')));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    });
    return store;
  }

  Finder draggable(String id) => find.byWidgetPredicate(
    (w) => w is LongPressDraggable<String> && w.data == id,
  );
  Future<TestGesture> pick(WidgetTester tester, String id) async {
    final rect = tester.getRect(draggable(id));
    final gesture = await tester.startGesture(
      rect.topLeft + const Offset(45, 40),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 180));
    return gesture;
  }

  Offset destination(WidgetTester tester) =>
      tester
          .getRect(find.byKey(const ValueKey('kanban-column-inProgress')))
          .topLeft +
      const Offset(80, 85);

  testWidgets(
    'drag reveals origin and insertion, waits for save, and undo restores source',
    (tester) async {
      final store = await boot(tester);
      final assignment = store.assignments.firstWhere(
        (a) => a.status == StudyStatus.todo,
      );
      store.gate = Completer<void>();
      final gesture = await pick(tester, assignment.id);
      expect(find.text('Исходное место'), findsOneWidget);
      await gesture.moveTo(destination(tester));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('board-drop-preview')), findsOneWidget);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.moves, 1);
      expect(find.text('Сохраняем…'), findsWidgets);
      expect(store.assignmentById(assignment.id)!.status, StudyStatus.todo);
      await tester.tap(find.text('Список'));
      await tester.pump();
      await tester.tap(find.text('Канбан'));
      await tester.pump();
      expect(find.text('Сохраняем…'), findsWidgets);
      store.gate!.complete();
      await tester.pumpAndSettle();
      expect(
        store.assignmentById(assignment.id)!.status,
        StudyStatus.inProgress,
      );
      expect(find.text('Исходное место'), findsNothing);
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(store.assignmentById(assignment.id)!.status, StudyStatus.todo);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('kanban undo notification expires without user interaction', (
    tester,
  ) async {
    final store = await boot(tester);
    final assignment = store.assignments.firstWhere(
      (a) => a.status == StudyStatus.todo,
    );
    final gesture = await pick(tester, assignment.id);
    await gesture.moveTo(destination(tester));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(store.assignmentById(assignment.id)!.status, StudyStatus.inProgress);
  });
  testWidgets(
    'failed drag returns card, retry succeeds without duplicate membership',
    (tester) async {
      final store = await boot(tester);
      final assignment = store.assignments.firstWhere(
        (a) => a.status == StudyStatus.todo,
      );
      store.fail = true;
      final gesture = await pick(tester, assignment.id);
      await gesture.moveTo(destination(tester));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        find.text('Не удалось сохранить перенос. Карточка возвращена.'),
        findsOneWidget,
      );
      expect(store.assignmentById(assignment.id)!.status, StudyStatus.todo);
      store.fail = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(
        store.assignmentById(assignment.id)!.status,
        StudyStatus.inProgress,
      );
      expect(
        store.assignments.where((a) => a.id == assignment.id),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('drop outside board cancels without a write', (tester) async {
    final store = await boot(tester);
    final assignment = store.assignments.firstWhere(
      (a) => a.status == StudyStatus.todo,
    );
    final gesture = await pick(tester, assignment.id);
    await gesture.moveTo(const Offset(850, 25));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.moves, 0);
    expect(find.text('Исходное место'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('drag can reorder within one column with reduced motion', (
    tester,
  ) async {
    final store = await boot(tester, reduced: true);
    final tasks =
        store.assignments.where((a) => a.status == StudyStatus.todo).toList()
          ..sort(compareStudyBoard);
    final gesture = await pick(tester, tasks.last.id);
    final column = tester.getRect(
      find.byKey(const ValueKey('kanban-column-todo')),
    );
    await gesture.moveTo(column.topLeft + const Offset(90, 70));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final ordered =
        store.assignments.where((a) => a.status == StudyStatus.todo).toList()
          ..sort(compareStudyBoard);
    expect(ordered.first.id, tasks.last.id);
    expect(store.moves, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('edge drag reveals the hidden last column on a phone', (
    tester,
  ) async {
    final store = await boot(tester, width: 390);
    final assignment = store.assignments.firstWhere(
      (a) => a.status == StudyStatus.todo,
    );
    final gesture = await pick(tester, assignment.id);
    final top = tester
        .getRect(find.byKey(const ValueKey('kanban-column-todo')))
        .top;
    await gesture.moveTo(Offset(383, top + 150));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final done = tester.getRect(
      find.byKey(const ValueKey('kanban-column-done')),
    );
    expect(done.left, lessThan(200));
    await gesture.moveTo(done.topLeft + const Offset(85, 85));
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.assignmentById(assignment.id)!.status, StudyStatus.done);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'C search stays across tabs; closing it clears query; back goes Today',
    (tester) async {
      await boot(tester, width: 390);
      expect(find.byKey(const ValueKey('assignments-search')), findsNothing);
      await tester.tap(find.byTooltip('Поиск заданий'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('assignments-search')),
        'лабораторная',
      );
      await tester.pumpAndSettle();
      final nav = find.byType(NavigationBar);
      await tester.tap(find.descendant(of: nav, matching: find.text('Пары')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: nav, matching: find.text('Задания')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('assignments-search')))
            .controller!
            .text,
        'лабораторная',
      );
      await tester.tap(find.byTooltip('Закрыть поиск'));
      await tester.pumpAndSettle();
      expect(find.text('Здесь пока нет заданий'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(nav).selectedIndex, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'profile labels stay above fields at narrow width and enlarged text',
    (tester) async {
      await boot(tester, width: 360, scale: 1.5);
      final nav = find.byType(NavigationBar);
      await tester.tap(
        find.descendant(of: nav, matching: find.text('Профиль')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Изменить профиль'));
      await tester.tap(find.text('Изменить профиль'));
      await tester.pumpAndSettle();
      for (final key in [
        'profile-name',
        'profile-group',
        'profile-course',
        'profile-subgroup',
      ]) {
        final field = tester.widget<TextFormField>(find.byKey(ValueKey(key)));
        final text = find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(TextField),
        );
        expect(tester.widget<TextField>(text).decoration!.labelText, isNull);
        expect(field, isNotNull);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
