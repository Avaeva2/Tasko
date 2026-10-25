import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/tasko_store.dart';
import '../models.dart';
import 'core_screens.dart';
import 'task_routes.dart';
import 'widgets.dart';

const _months = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];
DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
TaskoProject? _project(TaskoStore store, String id) {
  for (final project in store.projects) {
    if (project.id == id) return project;
  }
  return null;
}

Future<bool> _perform(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить изменение. Повторите попытку.'),
        ),
      );
    }
    return false;
  }
}

class _ScreenBody extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  const _ScreenBody({required this.children, this.maxWidth = 1000});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ListView(padding: EdgeInsets.all(padding), children: children),
        ),
      );
    },
  );
}

class _RouteScreen extends StatelessWidget {
  final String title;
  final Widget child;
  const _RouteScreen({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

class _ScreenTitle extends StatelessWidget {
  final String title;
  final String? detail;
  const _ScreenTitle(this.title, {this.detail});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(
            detail!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? colors.surfaceContainer
            : colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: padding,
      child: child,
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final TaskoProfile profile;
  const _ProfileAvatar(this.profile);
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 20,
    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
    foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
    child: Text(
      profile.initials,
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget field;
  const _LabeledField(this.label, this.field);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        field,
      ],
    ),
  );
}

class _UnavailableIntegration extends StatelessWidget {
  final IconData icon;
  final String title;
  const _UnavailableIntegration(this.icon, this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(
      label: '$title. Интеграция запланирована, пока недоступна.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            weight: 300,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.bodyLarge),
          ),
          const SizedBox(width: 12),
          Text(
            'Скоро',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class AuthScreen extends StatefulWidget {
  final TaskoStore store;
  const AuthScreen({super.key, required this.store});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _register = false;
  bool _obscure = true;
  bool _submitting = false;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      if (_register) {
        await widget.store.signUp(
          _name.text.trim(),
          _email.text.trim(),
          _password.text,
        );
        if (mounted &&
            !widget.store.isAuthenticated &&
            widget.store.error == null) {
          setState(
            () => _message = 'Проверьте почту: если включено подтверждение email, завершите регистрацию по ссылке в письме.',
          );
        }
      } else {
        await widget.store.signIn(_email.text.trim(), _password.text);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Не удалось войти. Проверьте данные и подключение, затем повторите.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final busy = _submitting || store.busy;
      final theme = Theme.of(context);
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: _ScreenBody(
            maxWidth: 520,
            children: [
              const SizedBox(height: 24),
              Text('Tasko', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 56),
              Text(
                _register
                    ? 'Создать рабочее пространство'
                    : 'Вход в рабочее пространство',
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Проекты, задачи и сроки в одном ритме.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_register)
                      _LabeledField(
                        'Ваше имя',
                        TextFormField(
                          controller: _name,
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Введите имя'
                              : null,
                        ),
                      ),
                    _LabeledField(
                      'Рабочая почта',
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch((value ?? '').trim())
                            ? null
                            : 'Введите корректную почту',
                      ),
                    ),
                    _LabeledField(
                      'Пароль',
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: [
                          _register
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        textInputAction: _register
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_register && !busy && store.hasBackend) {
                            _submit();
                          }
                        },
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Показать пароль'
                                : 'Скрыть пароль',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Symbols.visibility_sharp
                                  : Symbols.visibility_off_sharp,
                              weight: 300,
                            ),
                          ),
                        ),
                        validator: (value) => (value ?? '').isEmpty
                            ? 'Введите пароль'
                            : _register && (value ?? '').length < 8
                            ? 'Минимум 8 символов'
                            : null,
                      ),
                    ),
                    if (_register)
                      _LabeledField(
                        'Повторите пароль',
                        TextFormField(
                          controller: _confirmation,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!busy && store.hasBackend) _submit();
                          },
                          validator: (value) => value == _password.text
                              ? null
                              : 'Пароли не совпадают',
                        ),
                      ),
                    if (store.error != null || _message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            store.error ?? _message!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: store.error != null
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    if (!store.hasBackend)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Вход пока недоступен. Попробуйте Tasko в деморежиме.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    if (!_register)
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.check_box_sharp,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Вход сохраняется',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          const Tooltip(
                            message: 'Восстановление пароля скоро появится',
                            child: TextButton(
                              onPressed: null,
                              child: Text('Забыли пароль?'),
                            ),
                          ),
                        ],
                      ),
                    FilledButton(
                      onPressed: busy || !store.hasBackend ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          busy
                              ? 'Подождите…'
                              : _register
                              ? 'Зарегистрироваться'
                              : 'Войти',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              _register = !_register;
                              _message = null;
                              _form.currentState?.reset();
                            }),
                      child: Text(
                        _register
                            ? 'Уже есть аккаунт? Войти'
                            : 'Создать аккаунт',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('или', style: theme.textTheme.bodySmall),
                        ),
                        Expanded(
                          child: Divider(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => _submitting = true);
                              try {
                                await store.enterDemo();
                              } catch (_) {
                                if (mounted) {
                                  setState(
                                    () => _message = 'Не удалось открыть демо. Повторите попытку.',
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _submitting = false);
                                }
                              }
                            },
                      icon: const Icon(Symbols.play_circle_sharp, weight: 300),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Попробовать демо',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Демоданные сохраняются на этом устройстве.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class CalendarScreen extends StatefulWidget {
  final TaskoStore store;
  const CalendarScreen({super.key, required this.store});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selected = _day(DateTime.now());
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _moveMonth(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    _selected = DateTime(_month.year, _month.month, 1);
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final today = _day(DateTime.now());
      final start = _month.weekday - 1;
      final days = DateTime(_month.year, _month.month + 1, 0).day;
      final rows = ((start + days) / 7).ceil();
      final tasks = widget.store.tasks
          .where(
            (task) => task.dueDate != null && _day(task.dueDate!) == _selected,
          )
          .toList();
      return _RouteScreen(
        title: 'Календарь',
        child: _ScreenBody(
          maxWidth: 840,
          children: [
            const _ScreenTitle(
              'Календарь',
              detail:
                  'Сроки ваших задач. Внешние календари будут доступны позже.',
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_months[_month.month - 1]} ${_month.year}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Предыдущий месяц',
                  onPressed: () => _moveMonth(-1),
                  icon: const Icon(Symbols.chevron_left_sharp, weight: 300),
                ),
                IconButton(
                  tooltip: 'Следующий месяц',
                  onPressed: () => _moveMonth(1),
                  icon: const Icon(Symbols.chevron_right_sharp, weight: 300),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _selected = today;
                  _month = DateTime(today.year, today.month);
                }),
                icon: const Icon(Symbols.today_sharp, weight: 300),
                label: const Text('Сегодня'),
              ),
            ),
            const SizedBox(height: 8),
            _Panel(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Row(
                    children: ['П', 'В', 'С', 'Ч', 'П', 'С', 'В']
                        .map(
                          (day) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                day,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  for (var row = 0; row < rows; row++)
                    Row(
                      children: [
                        for (var column = 0; column < 7; column++)
                          Expanded(
                            child: _calendarCell(
                              context,
                              row * 7 + column - start + 1,
                              days,
                              today,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionHeading(
              'Задачи · ${dateLabel(_selected)}',
              trailing: Text(
                '${tasks.length}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            if (tasks.isEmpty)
              EmptyState(
                icon: Symbols.event_available_sharp,
                title: 'На этот день задач нет',
                detail: 'Добавьте задачу со сроком или выберите другой день.',
                action: TextButton.icon(
                  onPressed: widget.store.projects.isEmpty
                      ? null
                      : () => showTaskEditor(
                          context,
                          widget.store,
                          initialDueDate: _selected,
                        ),
                  icon: const Icon(Symbols.add_sharp, weight: 300),
                  label: const Text('Создать задачу'),
                ),
              ),
            for (final task in tasks)
              TaskRow(
                task: task,
                project: _project(widget.store, task.projectId),
                onTap: () => showTaskDetails(context, widget.store, task: task),
              ),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );

  Widget _calendarCell(
    BuildContext context,
    int number,
    int maxDay,
    DateTime today,
  ) {
    if (number < 1 || number > maxDay) return const SizedBox(height: 52);
    final date = DateTime(_month.year, _month.month, number);
    final selected = date == _selected;
    final current = date == today;
    final count = widget.store.tasks
        .where((task) => task.dueDate != null && _day(task.dueDate!) == date)
        .length;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: '${dateLabel(date)}, задач: $count',
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: InkWell(
          onTap: () => setState(() => _selected = date),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            decoration: BoxDecoration(
              color: selected ? colors.secondaryContainer : null,
              borderRadius: BorderRadius.circular(6),
              border: current ? Border.all(color: colors.primary) : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Text(
                  '$number',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selected
                        ? colors.onSecondaryContainer
                        : current
                        ? colors.primary
                        : colors.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: count > 0
                        ? colors.onSurfaceVariant
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReportsScreen extends StatefulWidget {
  final TaskoStore store;
  const ReportsScreen({super.key, required this.store});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String? _projectId;
  String _period = 'month';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final now = DateTime.now();
      final today = _day(now);
      final periodStart = _period == 'week'
          ? today.subtract(Duration(days: today.weekday - 1))
          : _period == 'month'
          ? DateTime(now.year, now.month)
          : null;
      final periodEnd = _period == 'week'
          ? periodStart!.add(const Duration(days: 7))
          : _period == 'month'
          ? DateTime(now.year, now.month + 1)
          : today.add(const Duration(days: 1));
      final selectedProject =
          widget.store.projects.any((project) => project.id == _projectId)
          ? _projectId
          : null;
      final tasks = widget.store.tasks
          .where(
            (task) =>
                selectedProject == null || task.projectId == selectedProject,
          )
          .toList();
      final done = tasks.where((task) => task.status == TaskStatus.done).length;
      final completed = tasks
          .where(
            (task) =>
                task.status == TaskStatus.done &&
                task.completedAt != null &&
                (periodStart == null ||
                    !task.completedAt!.isBefore(periodStart)) &&
                task.completedAt!.isBefore(periodEnd),
          )
          .length;
      final overdue = tasks.where((task) => task.overdue(now)).length;
      final progress = tasks.isEmpty ? 0.0 : done / tasks.length;
      final theme = Theme.of(context);
      return _RouteScreen(
        title: 'Отчёты',
        child: _ScreenBody(
          children: [
            const _ScreenTitle(
              'Отчёты',
              detail: 'Прогресс рассчитывается по вашим задачам.',
            ),
            _LabeledField(
              'Проект',
              DropdownButtonFormField<String>(
                key: ValueKey(selectedProject),
                initialValue: selectedProject ?? '',
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Все проекты')),
                  ...widget.store.projects.map(
                    (project) => DropdownMenuItem(
                      value: project.id,
                      child: Text(
                        project.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _projectId = value == '' ? null : value),
              ),
            ),
            _LabeledField(
              'Период завершения',
              DropdownButtonFormField<String>(
                initialValue: _period,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'week', child: Text('Эта неделя')),
                  DropdownMenuItem(value: 'month', child: Text('Этот месяц')),
                  DropdownMenuItem(value: 'all', child: Text('За всё время')),
                ],
                onChanged: (value) =>
                    setState(() => _period = value ?? 'month'),
              ),
            ),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(progress * 100).round()}%',
                    style: theme.textTheme.displayMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$done из ${tasks.length} задач завершено',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    color: theme.colorScheme.onSurface,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  const SizedBox(height: 20),
                  _MetricRow('Открыто сейчас', '${tasks.length - done}'),
                  _MetricRow(
                    'Просрочено сейчас',
                    '$overdue',
                    warning: overdue > 0,
                  ),
                  _MetricRow('Завершено за выбранный период', '$completed'),
                  const SizedBox(height: 12),
                  Text(
                    'Общий прогресс и открытые задачи отражают текущее состояние. Фильтр периода учитывает дату завершения задач.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionHeading('Распределение по статусам'),
            const SizedBox(height: 12),
            for (final status in TaskStatus.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: StatusChip(status: status),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${tasks.where((task) => task.status == status).length}',
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  ],
                ),
              ),
            if (tasks.isEmpty)
              EmptyState(
                icon: Symbols.monitoring_sharp,
                title: 'Пока нет данных для отчёта',
                detail: 'Создайте проект и задачи, чтобы увидеть прогресс.',
              ),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
}

class _MetricRow extends StatelessWidget {
  final String label, value;
  final bool warning;
  const _MetricRow(this.label, this.value, {this.warning = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 16),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: warning ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      ],
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  final TaskoStore store;
  const ProfileScreen({super.key, required this.store});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _role;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.store.profile.name);
    _role = TextEditingController(text: widget.store.profile.role);
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.store.saveProfile(_name.text.trim(), _role.text.trim());
      if (mounted && widget.store.error == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Профиль сохранён')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось сохранить профиль. Повторите.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => _RouteScreen(
      title: 'Профиль',
      child: _ScreenBody(
        maxWidth: 680,
        children: [
          _ScreenTitle(
            'Профиль',
            detail: widget.store.isDemo
                ? 'Демонстрационный профиль · данные на этом устройстве'
                : 'Ваш профиль в Tasko',
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileAvatar(widget.store.profile),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.store.profile.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.store.profile.email,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LabeledField(
                  'Имя',
                  TextFormField(
                    controller: _name,
                    maxLength: 80,
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Введите имя' : null,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                _LabeledField(
                  'Роль',
                  TextFormField(
                    controller: _role,
                    maxLength: 120,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) {
                      if (!_saving) _save();
                    },
                  ),
                ),
                if (widget.store.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      widget.store.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _saving || widget.store.busy ? null : _save,
                    icon: const Icon(Symbols.check_sharp, weight: 300),
                    label: Text(_saving ? 'Сохраняем…' : 'Сохранить'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.settings_sharp, weight: 300),
            title: const Text('Настройки'),
            trailing: const Icon(Symbols.chevron_right_sharp, weight: 300),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(store: widget.store),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

class _SettingsBand extends StatelessWidget {
  final Widget child;
  const _SettingsBand({required this.child});
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceContainer
        : Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Container(
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: child,
    ),
  );
}

class _SettingsLabel extends StatelessWidget {
  final String text;
  const _SettingsLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class SettingsScreen extends StatelessWidget {
  final TaskoStore store;
  const SettingsScreen({super.key, required this.store});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final theme = Theme.of(context);
      return _RouteScreen(
        title: 'Настройки',
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              children: [
                const SizedBox(height: 16),
                _SettingsBand(
                  child: ListTile(
                    leading: _ProfileAvatar(store.profile),
                    title: Text(store.profile.name),
                    subtitle: Text(
                      '${store.profile.email} · ${store.profile.role}',
                    ),
                    trailing: const Icon(Symbols.chevron_right_sharp),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ProfileScreen(store: store),
                      ),
                    ),
                  ),
                ),
                const _SettingsLabel('Оформление'),
                _SettingsBand(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Тема', style: theme.textTheme.bodyLarge),
                            const SizedBox(height: 10),
                            SegmentedButton<String>(
                              showSelectedIcon:
                                  MediaQuery.textScalerOf(context).scale(1) <
                                  1.3,
                              expandedInsets: EdgeInsets.zero,
                              segments: const [
                                ButtonSegment(
                                  value: 'system',
                                  label: Text('Система'),
                                ),
                                ButtonSegment(
                                  value: 'light',
                                  label: Text('Светлая'),
                                ),
                                ButtonSegment(
                                  value: 'dark',
                                  label: Text('Тёмная'),
                                ),
                              ],
                              selected: {store.theme},
                              onSelectionChanged: store.busy
                                  ? null
                                  : (values) => _perform(
                                      context,
                                      () => store.setTheme(values.single),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const ListTile(
                        title: Text('Размер текста'),
                        subtitle: Text('Как в системе'),
                      ),
                    ],
                  ),
                ),
                const _SettingsLabel('Уведомления'),
                _SettingsBand(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Напоминания о сроках'),
                        subtitle: const Text(
                          'Сегодня, завтра и просроченные — во «Входящих»',
                        ),
                        value: store.deadlineReminders,
                        onChanged: store.busy
                            ? null
                            : (value) => _perform(
                                context,
                                () => store.setDeadlineReminders(value),
                              ),
                      ),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const ListTile(
                        title: Text('Push-уведомления'),
                        subtitle: Text('Назначения, упоминания, смена статуса'),
                        trailing: Text('Скоро'),
                      ),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const ListTile(
                        title: Text('Сводка на почту'),
                        subtitle: Text('Письма о проектах и задачах'),
                        trailing: Text('Скоро'),
                      ),
                    ],
                  ),
                ),
                const _SettingsLabel('Интеграции'),
                _SettingsBand(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const _UnavailableIntegration(
                          Symbols.event_sharp,
                          'Google Календарь',
                        ),
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        const _UnavailableIntegration(
                          Symbols.download_sharp,
                          'Яндекс Трекер — импорт',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (store.error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      store.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: store.busy
                        ? null
                        : () async {
                            final leave = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: Text(
                                  store.isDemo
                                      ? 'Выйти из демо?'
                                      : 'Выйти из пространства?',
                                ),
                                content: Text(
                                  store.isDemo
                                      ? 'Локальные проекты и задачи сохранятся на этом устройстве.'
                                      : 'Для доступа к проектам потребуется снова войти.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text('Отмена'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: const Text('Выйти'),
                                  ),
                                ],
                              ),
                            );
                            if (leave == true && context.mounted) {
                              final success = await _perform(
                                context,
                                store.signOut,
                              );
                              if (success && context.mounted) {
                                Navigator.of(context)
                                    .popUntil((route) => route.isFirst);
                              }
                            }
                          },
                    icon: Icon(
                      Symbols.logout_sharp,
                      color: theme.colorScheme.error,
                    ),
                    label: Text(
                      store.isDemo ? 'Выйти из демо' : 'Выйти из пространства',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class TeamScreen extends StatefulWidget {
  final TaskoStore store;
  const TeamScreen({super.key, required this.store});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  bool month = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final theme = Theme.of(context);
      final now = _day(DateTime.now());
      final start = month
          ? DateTime(now.year, now.month, 1)
          : now.subtract(Duration(days: now.weekday - 1));
      final end = month
          ? DateTime(now.year, now.month + 1, 1)
          : start.add(const Duration(days: 7));
      final personalProjectIds = store.projects
          .where((p) => p.teamId == null && !p.archived)
          .map((p) => p.id)
          .toSet();
      final periodTasks = store.tasks
          .where(
            (task) =>
                personalProjectIds.contains(task.projectId) &&
                task.dueDate != null &&
                !task.dueDate!.isBefore(start) &&
                task.dueDate!.isBefore(end),
          )
          .toList();
      final open = periodTasks.where((t) => t.status != TaskStatus.done).length;
      final completed = periodTasks.length - open;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Команда',
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      const Tooltip(
                        message: 'Приглашения участников скоро появятся',
                        child: IconButton(
                          onPressed: null,
                          tooltip: 'Пригласить участника · Скоро',
                          icon: Icon(Symbols.person_add_sharp),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    expandedInsets: EdgeInsets.zero,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Неделя')),
                      ButtonSegment(value: true, label: Text('Месяц')),
                    ],
                    selected: {month},
                    onSelectionChanged: (value) =>
                        setState(() => month = value.single),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('$open', style: theme.textTheme.displaySmall),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'открытых задач со сроком за ${month ? 'месяц' : 'неделю'} · $completed завершено',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SectionHeading(
                    'Участники',
                    trailing: Text('1', style: theme.textTheme.bodySmall),
                  ),
                ),
                _SettingsBand(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileAvatar(store.profile),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                store.profile.name,
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                store.profile.role.isEmpty
                                    ? 'Участник'
                                    : store.profile.role,
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: periodTasks.isEmpty
                                    ? 0
                                    : completed / periodTasks.length,
                                minHeight: 8,
                                color: theme.colorScheme.secondary,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Вы · $completed из ${periodTasks.length} задач завершено',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Показаны ваши задачи. Приглашения и оценка загрузки в часах скоро появятся.',
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class InboxScreen extends StatefulWidget {
  final TaskoStore store;
  const InboxScreen({super.key, required this.store});
  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  int selected = 0;
  String reminderId(TaskoTask task) =>
      '${task.id}:${task.dueDate!.year}-${task.dueDate!.month.toString().padLeft(2, '0')}-${task.dueDate!.day.toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final theme = Theme.of(context);
      final today = _day(DateTime.now());
      final tomorrow = today.add(const Duration(days: 1));
      final reminders = store.deadlineReminders
          ? store.tasks
                .where(
                  (task) =>
                      task.status != TaskStatus.done &&
                      !(_project(store, task.projectId)?.archived ?? false) &&
                      task.dueDate != null &&
                      !_day(task.dueDate!).isAfter(tomorrow),
                )
                .toList()
          : <TaskoTask>[];
      reminders.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
      final unread = reminders
          .where((task) => !store.readReminderIds.contains(reminderId(task)))
          .length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Входящие',
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: unread == 0 || store.busy
                            ? null
                            : () => _perform(
                                context,
                                () => store.markRemindersRead(
                                  reminders.map(reminderId),
                                ),
                              ),
                        child: const Text('Прочитать все'),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (index, label) in [
                        'Все ${reminders.length}',
                        'Упоминания 0',
                        'Назначено 0',
                      ].indexed)
                        InkWell(
                          onTap: () => setState(() => selected = index),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  width: 2,
                                  color: selected == index
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                            child: Text(
                              label,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: selected == index
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: ListView(
              children: [
                if (!store.deadlineReminders)
                  const EmptyState(
                    icon: Symbols.notifications_off_sharp,
                    title: 'Напоминания отключены',
                    detail: 'Включите напоминания о сроках в настройках, чтобы видеть их здесь.',
                  )
                else if (selected != 0)
                  EmptyState(
                    icon: selected == 1
                        ? Symbols.alternate_email_sharp
                        : Symbols.person_check_sharp,
                    title: selected == 1 ? 'Нет упоминаний' : 'Нет назначений',
                    detail: 'Уведомления об участниках скоро появятся.',
                  )
                else if (reminders.isEmpty)
                  const EmptyState(
                    icon: Symbols.inbox_sharp,
                    title: 'Сейчас всё спокойно',
                    detail: 'Здесь появятся задачи со сроком сегодня, завтра или с просрочкой.',
                  )
                else
                  for (final (label, matches)
                      in <(String, bool Function(TaskoTask))>[
                        ('Сегодня', (task) => _day(task.dueDate!) == today),
                        ('Завтра', (task) => _day(task.dueDate!) == tomorrow),
                        ('Просроченные', (task) => task.overdue(today)),
                      ]) ...[
                    if (reminders.any(matches))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        color: theme.colorScheme.surfaceContainerLow,
                        child: Text(label, style: theme.textTheme.labelMedium),
                      ),
                    for (final task in reminders.where(matches))
                      InkWell(
                        onTap: () async {
                          await _perform(
                            context,
                            () => store.markRemindersRead([reminderId(task)]),
                          );
                          if (context.mounted) {
                            await showTaskDetails(context, store, task: task);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark
                                ? theme.colorScheme.surfaceContainer
                                : theme.colorScheme.surfaceContainerLowest,
                            border: Border(
                              bottom: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  right: 8,
                                ),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color:
                                        store.readReminderIds.contains(
                                          reminderId(task),
                                        )
                                        ? Colors.transparent
                                        : theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                                child: Icon(
                                  task.overdue(today)
                                      ? Symbols.event_busy_sharp
                                      : Symbols.event_sharp,
                                  size: 20,
                                  color: task.overdue(today)
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.overdue(today)
                                          ? 'Срок задачи прошёл'
                                          : 'Приближается срок задачи',
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      task.title,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_project(store, task.projectId)?.key ?? ''} · ${dateLabel(task.dueDate)}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
              ],
            ),
          ),
        ],
      );
    },
  );
}
