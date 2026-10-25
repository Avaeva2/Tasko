import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasko/student/student_app.dart';
import 'package:tasko/student/student_store.dart';

class _AuthStore extends StudentStore {
  _AuthStore() : super(persistDemo: false);
  int attempts = 0;
  @override
  bool get hasBackend => true;
  @override
  Future<void> login(String email, String password) async {
    attempts++;
    throw StateError('Не удалось подключиться. Повторите попытку.');
  }
}

void main() {
  for (final size in [
    const Size(360, 640),
    const Size(390, 844),
    const Size(430, 932),
    const Size(1280, 900),
  ]) {
    testWidgets('auth stays still and actions fit at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _AuthStore();
      await tester.pumpWidget(StudentApp(store: store));
      await tester.pumpAndSettle();
      final email = find.byKey(const ValueKey('student-auth-email'));
      final origin = tester.getTopLeft(email);
      await tester.drag(find.byType(StudentAuthScreen), const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(email), origin);
      expect(find.text('Попробовать демо').hitTestable(), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Создать аккаунт'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('student-auth-name')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Попробовать демо').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    });
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('keyboard and validation keep signup usable at scale $scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = _AuthStore();
      await tester.pumpWidget(StudentApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Создать аккаунт'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Создать аккаунт'));
      await tester.pumpAndSettle();
      expect(find.text('Введите имя'), findsOneWidget);
      expect(find.text('Введите корректную почту'), findsOneWidget);
      expect(find.text('Не менее 6 символов'), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Создать аккаунт').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Попробовать демо').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    });
  }

  testWidgets('failed login retains credentials and demo remains available', (
    tester,
  ) async {
    final store = _AuthStore();
    await tester.pumpWidget(StudentApp(store: store));
    await tester.pumpAndSettle();
    final email = find.byKey(const ValueKey('student-auth-email'));
    final password = find.byKey(const ValueKey('student-auth-password'));
    await tester.enterText(email, 'student@example.test');
    await tester.enterText(password, 'example-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pumpAndSettle();
    expect(store.attempts, 1);
    expect(find.textContaining('Не удалось подключиться'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(email).controller!.text,
      'student@example.test',
    );
    expect(
      tester.widget<TextFormField>(password).controller!.text,
      'example-pass',
    );
    await tester.tap(find.text('Попробовать демо'));
    await tester.pumpAndSettle();
    expect(find.byType(StudentShell), findsOneWidget);
    expect(store.isDemo, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
