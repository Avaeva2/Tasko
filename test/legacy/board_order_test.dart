import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/theme.dart';
import 'package:tasko/legacy/ui/core_screens.dart';

class _RecordingStore extends TaskoStore {
  _RecordingStore() : super(persistDemo: false);
  final List<(String, TaskStatus, String?)> calls = [];
  Completer<void>? gate;
  bool failNext = false;
  @override
  Future<void> moveTask(
    String id,
    TaskStatus status, {
    String? beforeTaskId,
  }) async {
    calls.add((id, status, beforeTaskId));
    if (gate != null) await gate!.future;
    if (failNext) {
      failNext = false;
      throw StateError('Запись не удалась');
    }
    await super.moveTask(id, status, beforeTaskId: beforeTaskId);
  }
}

Future<_RecordingStore> _fixture({
  bool filtered = false,
  bool destination = false,
}) async {
  final store = _RecordingStore();
  await store.enterDemo();
  store.projects = [
    const TaskoProject(id: 'project', name: 'Очередь проекта', key: 'QUEUE'),
  ];
  final date = DateTime(2026, 10, 7);
  store.tasks = [
    for (var index = 0; index < 3; index++)
      TaskoTask(
        id: ['a', 'b', 'c'][index],
        projectId: 'project',
        title: ['Первый', 'Скрытый сосед', 'Последний'][index],
        createdAt: date.add(Duration(minutes: index)),
        position: index,
        issueNumber: index + 1,
        issueType: index == 2 ? TaskIssueType.bug : TaskIssueType.task,
        priority: filtered && index == 1 ? TaskPriority.low : TaskPriority.high,
      ),
    if (destination)
      TaskoTask(
        id: 'd',
        projectId: 'project',
        title: 'В целевой колонке',
        status: TaskStatus.inProgress,
        createdAt: date,
        position: 0,
        issueNumber: 4,
      ),
  ];
  return store;
}

List<String> order(TaskoStore store, TaskStatus status) =>
    (store.tasks.where((task) => task.status == status).toList()
          ..sort((a, b) => a.position.compareTo(b.position)))
        .map((task) => task.id)
        .toList();

Future<void> mount(
  WidgetTester tester,
  TaskoStore store, {
  double width = 390,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ru')],
      theme: taskoTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: BoardScreen(store: store, projectId: 'project'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> drop(
  WidgetTester tester,
  String taskId,
  Finder target, {
  bool mouse = false,
  bool cancel = false,
}) async {
  final source = find.byKey(
    ValueKey(mouse ? 'board-mouse-drag-$taskId' : 'board-drag-$taskId'),
  );
  final gesture = await tester.startGesture(
    tester.getCenter(source),
    kind: mouse ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
  );
  if (!mouse) await tester.pump(const Duration(milliseconds: 300));
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 50));
  if (cancel) {
    await gesture.moveTo(const Offset(10, 5));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets(
    'Touch places last before first in same column and Undo restores order',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _fixture();
      addTearDown(store.dispose);
      await mount(tester, store);
      await drop(tester, 'c', find.byKey(const ValueKey('board-before-a')));
      expect(order(store, TaskStatus.todo), ['c', 'a', 'b']);
      expect(store.calls.single, ('c', TaskStatus.todo, 'a'));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('board-before-c'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('board-before-a'))).dy,
        ),
      );
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(order(store, TaskStatus.todo), ['a', 'b', 'c']);
      expect(store.calls.last, ('c', TaskStatus.todo, null));
      await store.refresh();
      await tester.pumpAndSettle();
      expect(order(store, TaskStatus.todo), ['a', 'b', 'c']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A new same-scope session cannot revive the previous board Undo',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _fixture();
      addTearDown(store.dispose);
      await mount(tester, store);
      await drop(tester, 'c', find.byKey(const ValueKey('board-before-a')));
      final savedTasks = [...store.tasks];
      final savedProjects = [...store.projects];
      final oldRevision = store.sessionRevision;
      await store.enterDemo();
      expect(store.sessionRevision, greaterThan(oldRevision));
      // Same IDs, status and rank must not make an old session's Undo valid.
      store.tasks = savedTasks;
      store.projects = savedProjects;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(store.calls, hasLength(1));
      expect(order(store, TaskStatus.todo), ['c', 'a', 'b']);
      expect(find.textContaining('Отмена недоступна'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mouse drag is immediate and cross column drop inserts before anchor',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _fixture(destination: true);
      addTearDown(store.dispose);
      await mount(tester, store, width: 1440);
      await drop(
        tester,
        'c',
        find.byKey(const ValueKey('board-before-d')),
        mouse: true,
      );
      expect(order(store, TaskStatus.todo), ['a', 'b']);
      expect(order(store, TaskStatus.inProgress), ['c', 'd']);
      expect(store.calls.single, ('c', TaskStatus.inProgress, 'd'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Empty column append accepts a task and creates position', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _fixture();
    addTearDown(store.dispose);
    await mount(tester, store, width: 1440);
    await drop(
      tester,
      'a',
      find.byKey(const ValueKey('board-append-review')),
      mouse: true,
    );
    expect(order(store, TaskStatus.review), ['a']);
    expect(store.calls.single, ('a', TaskStatus.review, null));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Filtered reorder anchors by full IDs and Undo restores hidden neighbor',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _fixture(filtered: true);
      addTearDown(store.dispose);
      await mount(tester, store);
      await tester.tap(find.byTooltip('Фильтр по приоритету'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Высокий'));
      await tester.pumpAndSettle();
      expect(find.text('Скрытый сосед'), findsNothing);
      await drop(tester, 'a', find.byKey(const ValueKey('board-before-c')));
      expect(order(store, TaskStatus.todo), ['b', 'a', 'c']);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(order(store, TaskStatus.todo), ['a', 'b', 'c']);
      expect(store.calls.last, ('a', TaskStatus.todo, 'b'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Self drop and cancel do not write data', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _fixture();
    addTearDown(store.dispose);
    await mount(tester, store);
    await drop(tester, 'a', find.byKey(const ValueKey('board-before-a')));
    expect(store.calls, isEmpty);
    await drop(
      tester,
      'c',
      find.byKey(const ValueKey('board-before-a')),
      cancel: true,
    );
    expect(store.calls, isEmpty);
    expect(order(store, TaskStatus.todo), ['a', 'b', 'c']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Append in a filtered empty view is end of real column', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _fixture(filtered: true, destination: true);
    addTearDown(store.dispose);
    store.tasks = store.tasks
        .map((t) => t.id == 'd' ? t.copyWith(priority: TaskPriority.low) : t)
        .toList();
    await mount(tester, store, width: 1440);
    await tester.tap(find.byTooltip('Фильтр по приоритету'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Высокий'));
    await tester.pumpAndSettle();
    expect(find.text('В целевой колонке'), findsNothing);
    await drop(
      tester,
      'a',
      find.byKey(const ValueKey('board-append-inProgress')),
      mouse: true,
    );
    expect(order(store, TaskStatus.inProgress), ['d', 'a']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Pending placement blocks a second drag and handles delayed success',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _fixture();
      addTearDown(store.dispose);
      store.gate = Completer<void>();
      await mount(tester, store);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('board-drag-c'))),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('board-before-a'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(store.calls.length, 1);
      expect(find.byKey(const ValueKey('board-saving-c')), findsOneWidget);
      expect(
        tester
            .widget<Draggable<TaskoTask>>(
              find.byKey(const ValueKey('board-mouse-drag-c')),
            )
            .maxSimultaneousDrags,
        0,
      );
      expect(order(store, TaskStatus.todo), ['a', 'b', 'c']);
      store.gate!.complete();
      await tester.pumpAndSettle();
      expect(order(store, TaskStatus.todo), ['c', 'a', 'b']);
      expect(find.byKey(const ValueKey('board-saving-c')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Failed placement preserves confirmed order and allows retry', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _fixture();
    addTearDown(store.dispose);
    store.failNext = true;
    await mount(tester, store);
    await drop(tester, 'c', find.byKey(const ValueKey('board-before-a')));
    expect(order(store, TaskStatus.todo), ['a', 'b', 'c']);
    expect(find.textContaining('Запись не удалась'), findsOneWidget);
    await drop(tester, 'c', find.byKey(const ValueKey('board-before-a')));
    expect(order(store, TaskStatus.todo), ['c', 'a', 'b']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Undo refuses stale order after a newer placement', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _fixture();
    addTearDown(store.dispose);
    await mount(tester, store);
    await drop(tester, 'c', find.byKey(const ValueKey('board-before-a')));
    await store.moveTask('c', TaskStatus.inProgress);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(order(store, TaskStatus.inProgress), ['c']);
    expect(
      find.text('Задача или её очередь уже изменились. Отмена недоступна.'),
      findsOneWidget,
    );
    expect(store.calls.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Same column append restores first anchor and last append is no-op',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _fixture();
      addTearDown(store.dispose);
      await mount(tester, store);
      await drop(tester, 'c', find.byKey(const ValueKey('board-append-todo')));
      expect(store.calls, isEmpty);
      await drop(tester, 'a', find.byKey(const ValueKey('board-append-todo')));
      expect(order(store, TaskStatus.todo), ['b', 'c', 'a']);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(order(store, TaskStatus.todo), ['a', 'b', 'c']);
      expect(store.calls.last, ('a', TaskStatus.todo, 'b'));
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'Board $width at 150 percent text preserves drag and card metadata',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await _fixture();
        addTearDown(store.dispose);
        await mount(
          tester,
          store,
          width: width,
          scale: 1.5,
          brightness: Brightness.dark,
        );
        expect(find.byTooltip('Ошибка'), findsOneWidget);
        await drop(tester, 'c', find.byKey(const ValueKey('board-before-a')));
        expect(order(store, TaskStatus.todo), ['c', 'a', 'b']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
