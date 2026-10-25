import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'student_store.dart';
import 'student_theme.dart';
import 'student_widgets.dart';
import 'student_screens.dart';
import 'student_assignment_screens.dart';

/// Primary student app. The bootstrap initializes [store] before runApp.
class StudentApp extends StatelessWidget {
  const StudentApp({super.key, required this.store});
  final StudentStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      title: 'Tasko · студенческий планер',
      debugShowCheckedModeBanner: false,
      theme: StudentTheme.light,
      locale: const Locale('ru', 'RU'),
      supportedLocales: const [Locale('ru', 'RU'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      home: store.authenticated
          ? StudentShell(store: store)
          : StudentAuthScreen(store: store),
    ),
  );
}

class StudentShell extends StatefulWidget {
  const StudentShell({super.key, required this.store});
  final StudentStore store;
  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _selected = 0, _direction = 1;
  bool _boardInteraction = false;
  Timer? _clock;
  static const _labels = ['Сегодня', 'Задания', 'Пары', 'Профиль'];
  static const _icons = [
    'calendar-blank',
    'squares-four',
    'graduation-cap',
    'user-circle',
  ];
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _select(int value) {
    if (value == _selected || _boardInteraction) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _direction = value > _selected ? 1 : -1;
      _selected = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final pages = [
      StudentTodayScreen(store: widget.store, onAssignments: () => _select(1)),
      StudentAssignmentsScreen(
        store: widget.store,
        onInteractionChanged: (value) {
          if (mounted) setState(() => _boardInteraction = value);
        },
      ),
      StudentScheduleScreen(store: widget.store),
      StudentProfileScreen(store: widget.store, onSchedule: () => _select(2)),
    ];
    return PopScope(
      canPop: _selected == 0 && !_boardInteraction,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_boardInteraction && _selected != 0) _select(0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: _selected == 0
              ? const StudentBrand()
              : Text(
                  _labels[_selected],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
          actions: [
            if (widget.store.isDemo)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                child: StudentBadge('Демо'),
              ),
            if (_selected == 1)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton.filled(
                  tooltip: 'Добавить задание',
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _boardInteraction
                      ? null
                      : () => showCreateStudyAssignment(context, widget.store),
                  icon: const StudentIcon('plus', color: Colors.white),
                ),
              )
            else
              IconButton(
                tooltip: 'Уведомления',
                onPressed: () =>
                    showStudentNotifications(context, widget.store),
                icon: const StudentIcon('bell-simple'),
              ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: [
              if (wide)
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      right: BorderSide(color: StudentColors.border),
                    ),
                  ),
                  child: NavigationRail(
                    selectedIndex: _selected,
                    onDestinationSelected: _select,
                    extended: true,
                    minExtendedWidth: 210,
                    backgroundColor: Colors.white,
                    indicatorColor: StudentColors.cream.withValues(alpha: .65),
                    destinations: List.generate(
                      4,
                      (i) => NavigationRailDestination(
                        icon: StudentIcon(
                          _icons[i],
                          color: _selected == i
                              ? StudentColors.accent
                              : StudentColors.muted,
                        ),
                        label: Text(_labels[i]),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        for (var i = 0; i < pages.length; i++)
                          StudentSectionScene(
                            key: ValueKey('section-$i'),
                            active: i == _selected,
                            direction: _direction,
                            child: pages[i],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: StudentColors.border)),
                ),
                child: NavigationBar(
                  selectedIndex: _selected,
                  onDestinationSelected: _select,
                  destinations: List.generate(
                    4,
                    (i) => NavigationDestination(
                      icon: StudentIcon(_icons[i], color: StudentColors.muted),
                      selectedIcon: StudentIcon(
                        _icons[i],
                        color: StudentColors.accent,
                      ),
                      label: _labels[i],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class StudentAuthScreen extends StatefulWidget {
  const StudentAuthScreen({super.key, required this.store});
  final StudentStore store;
  @override
  State<StudentAuthScreen> createState() => _StudentAuthScreenState();
}

class _StudentAuthScreenState extends State<StudentAuthScreen> {
  final _form = GlobalKey<FormState>(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _name = TextEditingController();
  bool _signup = false, _busy = false, _obscure = true;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !widget.store.hasBackend) return;
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signup) {
        await widget.store.signUp(
          _email.text.trim(),
          _password.text,
          _name.text.trim(),
        );
        if (mounted && !widget.store.authenticated) {
          showStudentMessage(
            context,
            'Регистрация отправлена. Если включено подтверждение, проверьте почту.',
          );
        }
      } else {
        await widget.store.login(_email.text.trim(), _password.text);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(
    String label,
    String hint,
    String icon, {
    required bool compact,
    Widget? suffix,
  }) => InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    contentPadding: EdgeInsets.symmetric(
      horizontal: 14,
      vertical: compact ? 12 : 16,
    ),
    prefixIcon: Padding(
      padding: const EdgeInsets.all(13),
      child: StudentIcon(icon, size: 22),
    ),
    suffixIcon: suffix,
    errorStyle: const TextStyle(fontSize: 11, height: 1.1),
    errorMaxLines: 1,
  );

  Future<void> _demo() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await widget.store.enterDemo();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight < 650 ||
              MediaQuery.viewInsetsOf(context).bottom > 0;
          final tight = constraints.maxHeight < 420;
          final gap = tight
              ? 6.0
              : compact
              ? 10.0
              : 16.0;
          final textStyle = TextStyle(
            fontSize: compact ? 14 : 16,
            height: 1.25,
          );
          final error = _error ?? widget.store.error;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 438, maxHeight: 840),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  tight ? 6 : 20,
                  24,
                  tight ? 6 : 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact) ...[
                      const StudentBrand(),
                      const SizedBox(height: 16),
                    ],
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: AutofillGroup(
                          child: Form(
                            key: _form,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!tight) ...[
                                  Text(
                                    compact
                                        ? (_signup
                                              ? 'Создать аккаунт'
                                              : 'Войти в Tasko')
                                        : (_signup
                                              ? 'Начните свой\nучебный план'
                                              : 'Учёба\nв своём ритме'),
                                    style: TextStyle(
                                      fontSize: compact ? 24 : 34,
                                      height: 1.15,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.6,
                                    ),
                                  ),
                                  if (!compact) ...[
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Пары, задания и сроки в одном месте.',
                                      style: TextStyle(
                                        fontSize: 15,
                                        height: 1.4,
                                        color: StudentColors.muted,
                                      ),
                                    ),
                                  ],
                                  SizedBox(height: compact ? 16 : 28),
                                ],
                                if (_signup) ...[
                                  TextFormField(
                                    key: const ValueKey('student-auth-name'),
                                    controller: _name,
                                    enabled: !_busy,
                                    style: textStyle,
                                    autofillHints: const [AutofillHints.name],
                                    textInputAction: TextInputAction.next,
                                    decoration: _decoration(
                                      'Имя',
                                      'Как к вам обращаться',
                                      'user-circle',
                                      compact: compact,
                                    ),
                                    validator: (v) =>
                                        !_signup ||
                                            v != null && v.trim().isNotEmpty
                                        ? null
                                        : 'Введите имя',
                                  ),
                                  SizedBox(height: gap),
                                ],
                                TextFormField(
                                  key: const ValueKey('student-auth-email'),
                                  controller: _email,
                                  enabled: !_busy,
                                  style: textStyle,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  textInputAction: TextInputAction.next,
                                  decoration: _decoration(
                                    'Электронная почта',
                                    'student@university.ru',
                                    'envelope-simple',
                                    compact: compact,
                                  ),
                                  validator: (v) =>
                                      v != null &&
                                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                              .hasMatch(v.trim())
                                      ? null
                                      : 'Введите корректную почту',
                                ),
                                SizedBox(height: gap),
                                TextFormField(
                                  key: const ValueKey('student-auth-password'),
                                  controller: _password,
                                  enabled: !_busy,
                                  style: textStyle,
                                  obscureText: _obscure,
                                  autofillHints: [
                                    _signup
                                        ? AutofillHints.newPassword
                                        : AutofillHints.password,
                                  ],
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: _decoration(
                                    'Пароль',
                                    'Не менее 6 символов',
                                    'lock-key',
                                    compact: compact,
                                    suffix: IconButton(
                                      tooltip: _obscure
                                          ? 'Показать пароль'
                                          : 'Скрыть пароль',
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (v) => v != null && v.length >= 6
                                      ? null
                                      : 'Не менее 6 символов',
                                ),
                                SizedBox(height: gap + (tight ? 0 : 4)),
                                if (error != null) ...[
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      error,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.3,
                                        color: StudentColors.danger,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: gap),
                                ],
                                if (!widget.store.hasBackend && !tight) ...[
                                  const Text(
                                    'Вход в аккаунт пока недоступен. Можно открыть демо.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.3,
                                      color: StudentColors.muted,
                                    ),
                                  ),
                                  SizedBox(height: gap),
                                ],
                                StudentButton(
                                  label: _signup ? 'Создать аккаунт' : 'Войти',
                                  busy: _busy,
                                  onPressed: widget.store.hasBackend
                                      ? _submit
                                      : null,
                                ),
                                SizedBox(height: tight ? 2 : 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 10,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 13,
                                          ),
                                        ),
                                        onPressed: _busy
                                            ? null
                                            : () => setState(() {
                                                _signup = !_signup;
                                                _error = null;
                                              }),
                                        child: Text(
                                          _signup ? 'Войти' : 'Создать аккаунт',
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 10,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 13,
                                          ),
                                        ),
                                        onPressed: _busy ? null : _demo,
                                        child: const Text(
                                          'Попробовать демо',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Учебные примеры в демо сохраняются на этом устройстве.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: StudentColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
