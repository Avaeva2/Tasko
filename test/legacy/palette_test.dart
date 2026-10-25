import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasko/legacy/models.dart';
import 'package:tasko/legacy/theme.dart';
import 'package:tasko/legacy/ui/widgets.dart';

// Color.computeLuminance uses the WCAG sRGB conversion and channel weights.
double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('original Tasko v2 colors and status tokens remain unchanged', () {
    final light = taskoTheme(Brightness.light);
    final dark = taskoTheme(Brightness.dark);
    expect(light.colorScheme.primary, const Color(0xFFAD4C0C));
    expect(dark.colorScheme.primary, const Color(0xFFF08A4B));
    expect(light.colorScheme.secondary, const Color(0xFF3E5366));
    expect(dark.colorScheme.secondary, const Color(0xFFA9BCCD));
    expect(light.scaffoldBackgroundColor, const Color(0xFFE9EEF2));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF0C141C));
    expect(light.cardTheme.color, Colors.white);
    expect(dark.cardTheme.color, const Color(0xFF172230));
    expect(light.inputDecorationTheme.fillColor, Colors.white);
    expect(dark.inputDecorationTheme.fillColor, const Color(0xFF172230));
    const lightStatuses = [
      [0xFF5E6F82, 0xFFE6EBF0, 0xFF2E3D4C],
      [0xFF1F6FB2, 0xFFE0ECF7, 0xFF154E7E],
      [0xFF0E7C86, 0xFFDCF0F1, 0xFF0A5960],
      [0xFFB3264E, 0xFFF7E0E6, 0xFF8A1C3C],
      [0xFF4F7A28, 0xFFE6EFDB, 0xFF3A5A1C],
    ];
    const darkStatuses = [
      [0xFF8D9DAE, 0xFF1E2A37, 0xFFB9C6D2],
      [0xFF5FA6E3, 0xFF13283C, 0xFFA3CDF0],
      [0xFF43B7C0, 0xFF0F2D31, 0xFF93D8DD],
      [0xFFEF6E8F, 0xFF35151F, 0xFFF5A8BB],
      [0xFF93BD66, 0xFF1B2B15, 0xFFBBD89F],
    ];
    for (final status in TaskStatus.values) {
      for (final brightness in Brightness.values) {
        final expected = brightness == Brightness.light
            ? lightStatuses[status.index]
            : darkStatuses[status.index];
        final palette = StatusPalette.of(status, brightness);
        expect(palette.foreground, Color(expected[0]));
        expect(palette.background, Color(expected[1]));
        expect(palette.ink, Color(expected[2]));
      }
    }
  });

  for (final brightness in Brightness.values) {
    test('$brightness text, actions and controls pass contrast thresholds', () {
      final theme = taskoTheme(brightness);
      final cs = theme.colorScheme;
      final pairs = <String, (Color, Color)>{
        'primary': (cs.onPrimary, cs.primary),
        'primaryContainer': (cs.onPrimaryContainer, cs.primaryContainer),
        'secondary': (cs.onSecondary, cs.secondary),
        'secondaryContainer': (cs.onSecondaryContainer, cs.secondaryContainer),
        'error': (cs.onError, cs.error),
        'errorContainer': (cs.onErrorContainer, cs.errorContainer),
        'snackbar': (cs.onInverseSurface, cs.inverseSurface),
      };
      for (final pair in pairs.entries) {
        expect(
          contrast(pair.value.$1, pair.value.$2),
          greaterThanOrEqualTo(4.5),
          reason: pair.key,
        );
      }
      final surfaces = <String, Color>{
        'page': theme.scaffoldBackgroundColor,
        'surface': cs.surface,
        'card': cs.surfaceContainerLowest,
        'low': cs.surfaceContainerLow,
        'column': cs.surfaceContainer,
        'high': cs.surfaceContainerHigh,
        'highest': cs.surfaceContainerHighest,
      };
      for (final surface in surfaces.entries) {
        for (final text in [cs.onSurface, cs.onSurfaceVariant]) {
          expect(
            contrast(text, surface.value),
            greaterThanOrEqualTo(4.5),
            reason: 'Text on ${surface.key}',
          );
        }
        for (final status in TaskStatus.values) {
          final palette = StatusPalette.of(status, brightness);
          expect(
            contrast(palette.foreground, surface.value),
            greaterThanOrEqualTo(3),
            reason: '${status.name} icon on ${surface.key}',
          );
        }
      }
      // Active inputs and outlined controls use card/surface backgrounds.
      // Low-contrast decorative outlines on other containers are deliberately
      // not presented as passing controls; their exact v2 colors are retained.
      for (final background in [
        cs.surface,
        theme.inputDecorationTheme.fillColor!,
        theme.cardTheme.color!,
      ]) {
        expect(contrast(cs.outline, background), greaterThanOrEqualTo(3));
        expect(contrast(cs.primary, background), greaterThanOrEqualTo(4.5));
      }
      for (final status in TaskStatus.values) {
        final palette = StatusPalette.of(status, brightness);
        expect(
          contrast(palette.ink, palette.background),
          greaterThanOrEqualTo(4.5),
          reason: '${status.name} label',
        );
        expect(
          contrast(palette.foreground, palette.background),
          greaterThanOrEqualTo(3),
          reason: '${status.name} icon',
        );
      }
    });

    testWidgets('$brightness v2 surfaces and status chips at 150% on 320px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late BuildContext bodyContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: taskoTheme(brightness),
          home: Builder(
            builder: (context) {
              bodyContext = context;
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: Scaffold(
                  appBar: AppBar(title: const Text('Задача')),
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('Проверить палитру Tasko v2'),
                      const SizedBox(height: 16),
                      const TextField(
                        decoration: InputDecoration(labelText: 'Название'),
                      ),
                      const SizedBox(height: 16),
                      for (final status in TaskStatus.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: StatusChip(status: status),
                          ),
                        ),
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Сохранить'),
                      ),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Отмена'),
                      ),
                      const FilledButton(
                        onPressed: null,
                        child: Text('Сохраняем…'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        TaskoColors.card(bodyContext),
        Theme.of(bodyContext).cardTheme.color,
      );
      expect(
        TaskoColors.column(bodyContext),
        brightness == Brightness.light
            ? const Color(0xFFEEF2F5)
            : const Color(0xFF131E28),
      );
      expect(
        TaskoColors.background(bodyContext),
        Theme.of(bodyContext).scaffoldBackgroundColor,
      );
      expect(find.byType(StatusChip), findsNWidgets(TaskStatus.values.length));
      // Distinct icons and readable labels preserve meaning without color alone.
      expect(
        TaskStatus.values
            .map((s) => StatusPalette.of(s, brightness).icon)
            .toSet()
            .length,
        TaskStatus.values.length,
      );
      for (final status in TaskStatus.values) {
        expect(find.text(status.label), findsOneWidget);
      }
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
