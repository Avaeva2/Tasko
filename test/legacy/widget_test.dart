import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasko/legacy/legacy_main.dart';
import 'package:tasko/legacy/data/tasko_store.dart';

void main() {
  testWidgets(
    'app opens Auth, explicit demo opens all five navigation sections',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TaskoStore(persistDemo: false);
      await store.initialize();
      await tester.pumpWidget(TaskoApp(store: store));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      await store.enterDemo();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      for (final name in [
        'Задачи',
        'Проекты',
        'Команда',
        'Входящие',
        'Сводка',
      ]) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(name),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await store.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      store.dispose();
    },
  );
}
