import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';

import 'timeline_screen.dart';
import 'task_routes.dart';

import '../models.dart';
import '../theme.dart';
import '../data/tasko_store.dart';
import '../data/task_query.dart';
import '../data/task_views.dart';
import 'task_filters_sheet.dart';
import 'widgets.dart';

import 'package:material_symbols_icons/symbols.dart';

TaskoProject? _project(TaskoStore store, String id) {
  for (final project in store.projects) {
    if (project.id == id) return project;
  }
  return null;
}

Color _card(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Theme.of(context).colorScheme.surfaceContainer
    : Theme.of(context).colorScheme.surfaceContainerLowest;

Color _statusColor(BuildContext context, TaskStatus status) {
  return StatusPalette.of(status, Theme.of(context).brightness).foreground;
}

IconData _statusIcon(TaskStatus status) => const [
  Symbols.radio_button_unchecked_sharp,
  Symbols.clock_loader_40_sharp,
  Symbols.visibility_sharp,
  Symbols.block_sharp,
  Symbols.check_circle_sharp,
][status.index];

IconData _priorityIcon(TaskPriority priority) => const [
  Symbols.signal_cellular_alt_1_bar_sharp,
  Symbols.signal_cellular_alt_2_bar_sharp,
  Symbols.signal_cellular_alt_sharp,
  Symbols.error_sharp,
][priority.index];

void _error(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
}

class _PageHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const _PageHeader(this.title, {this.actions = const []});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final TaskoStore store;
  final VoidCallback onProjects, onCalendar, onReports;
  final VoidCallback? onProfile;
  const DashboardScreen({
    super.key,
    required this.store,
    required this.onProjects,
    required this.onCalendar,
    required this.onReports,
    this.onProfile,
  });
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool searching = false;
  String query = '';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final store = widget.store;
        final expanded = constraints.maxWidth > 840;
        final colors = Theme.of(context).colorScheme;
        final now = DateTime.now();
        final day = DateTime(now.year, now.month, now.day);
        final active = store.tasks
            .where(
              (t) =>
                  t.status != TaskStatus.done &&
                  !(_project(store, t.projectId)?.archived ?? false),
            )
            .toList();
        final today =
            active
                .where(
                  (t) =>
                      t.dueDate != null &&
                      t.dueDate!.isBefore(day.add(const Duration(days: 1))),
                )
                .toList()
              ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
        final deadlines = active.where((t) => t.dueDate != null).toList()
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
        final attention = active
            .where((t) => t.status == TaskStatus.blocked || t.overdue(now))
            .toList();
        final matches = store.tasks
            .where(
              (t) => '${t.title} ${_project(store, t.projectId)?.key ?? ''}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
            )
            .toList();
        Widget heading(String title, {Widget? trailing}) => Padding(
          padding: EdgeInsets.fromLTRB(
            expanded ? 0 : 16,
            24,
            expanded ? 0 : 16,
            8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: expanded
                      ? Theme.of(context).textTheme.headlineSmall
                      : Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?trailing,
            ],
          ),
        );
        Widget rows(List<TaskoTask> tasks) => Container(
          decoration: BoxDecoration(
            color: _card(context),
            border: Border.all(color: colors.outlineVariant),
            borderRadius: expanded ? BorderRadius.circular(10) : null,
          ),
          child: Column(
            children: tasks
                .map(
                  (t) => _CoreTaskRow(
                    task: t,
                    store: store,
                    onTap: () => showTaskDetails(context, store, task: t),
                  ),
                )
                .toList(),
          ),
        );
        Widget todaySection() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading(
              'Мои задачи на сегодня',
              trailing: Text(
                '${today.length}',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            if (today.isEmpty)
              EmptyState(
                icon: Symbols.checklist_sharp,
                title: 'На сегодня всё спокойно',
                detail: 'Задачи со сроком сегодня или раньше появятся здесь.',
                action: TextButton(
                  onPressed: () => showTaskEditor(context, store),
                  child: const Text('Добавить задачу'),
                ),
              )
            else
              rows(today),
            if (expanded) ...[
              heading('Требует внимания'),
              if (attention.isEmpty)
                Text(
                  'Нет заблокированных и просроченных задач.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                )
              else
                ...attention
                    .take(3)
                    .map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _card(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              if (t.description.isNotEmpty) ...[
                                Text(
                                  t.description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 8),
                              ],
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  StatusChip(status: t.status),
                                  if (t.overdue(now))
                                    Text(
                                      'Просрочено · ${dateLabel(t.dueDate)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: colors.error),
                                    ),
                                  OutlinedButton(
                                    onPressed: () => showTaskDetails(
                                      context,
                                      store,
                                      task: t,
                                    ),
                                    child: const Text('Открыть'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ],
          ],
        );
        Widget sideSections() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading('Ближайшие дедлайны'),
            if (deadlines.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 0 : 16,
                  vertical: 12,
                ),
                child: const Text('Пока нет задач со сроком'),
              )
            else
              ...deadlines
                  .take(expanded ? 5 : 3)
                  .map(
                    (t) => InkWell(
                      onTap: () => showTaskDetails(context, store, task: t),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: expanded ? 0 : 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: colors.outlineVariant),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: expanded ? 80 : 64,
                              child: Text(
                                dateLabel(t.dueDate),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontFamily: 'JetBrains Mono',
                                      color: t.overdue(now)
                                          ? colors.error
                                          : colors.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _project(store, t.projectId)?.name ?? '',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            heading(
              'Проекты',
              trailing: TextButton(
                onPressed: widget.onProjects,
                child: const Text('Все'),
              ),
            ),
            if (store.projects.where((p) => !p.archived).isEmpty)
              EmptyState(
                icon: Symbols.folder_open_sharp,
                title: 'Начните с проекта',
                detail: 'Объедините задачи и выберите первый шаг.',
                action: FilledButton(
                  onPressed: () => showProjectEditor(context, store),
                  child: const Text('Создать проект'),
                ),
              )
            else
              ...store.projects
                  .where((p) => !p.archived)
                  .take(expanded ? 4 : 2)
                  .map((p) {
                    final tasks = store.tasks
                        .where((t) => t.projectId == p.id)
                        .toList();
                    final done = tasks
                        .where((t) => t.status == TaskStatus.done)
                        .length;
                    final progress = tasks.isEmpty ? 0.0 : done / tasks.length;
                    return InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              BoardScreen(store: store, projectId: p.id),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          expanded ? 0 : 16,
                          8,
                          expanded ? 0 : 16,
                          12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  expanded
                                      ? '$done из ${tasks.length}'
                                      : '${(progress * 100).round()}%',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (expanded)
                              _ProjectStatusBar(tasks: tasks)
                            else
                              LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                color: colors.onSurface,
                                backgroundColor: colors.surfaceContainerHighest,
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
          ],
        );
        return Scaffold(
          body: Column(
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(
                  expanded ? 40 : 16,
                  expanded ? 32 : 8,
                  expanded ? 40 : 8,
                  expanded ? 24 : 12,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(
                    bottom: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expanded
                                ? DateFormat(
                                    'EEEE, d MMMM yyyy',
                                    'ru',
                                  ).format(now)
                                : DateFormat('EE, d MMM', 'ru').format(now),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontFamily: 'JetBrains Mono',
                                  color: colors.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Сводка',
                            style: expanded
                                ? Theme.of(context).textTheme.displayMedium
                                : Theme.of(context).textTheme.headlineMedium,
                          ),
                          if (expanded) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${today.length} задач на сегодня. ${active.where((t) => t.status == TaskStatus.review).length} ждут ревью, ${active.where((t) => t.status == TaskStatus.blocked).length} заблокированы.',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (expanded)
                      FilledButton.icon(
                        onPressed: () => showTaskEditor(context, store),
                        icon: const Icon(Symbols.add_sharp, size: 20),
                        label: const Text('Создать задачу'),
                      )
                    else ...[
                      IconButton(
                        tooltip: 'Поиск задач',
                        onPressed: () => setState(() => searching = !searching),
                        icon: const Icon(Symbols.search_sharp, size: 24),
                      ),
                      IconButton(
                        tooltip: 'Профиль',
                        onPressed: widget.onProfile,
                        icon: CircleAvatar(
                          radius: 16,
                          backgroundColor: colors.secondaryContainer,
                          foregroundColor: colors.onSecondaryContainer,
                          child: Text(
                            store.profile.initials,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Календарь и отчёты',
                        onSelected: (action) => action == 'calendar'
                            ? widget.onCalendar()
                            : widget.onReports(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'calendar',
                            child: Text('Календарь'),
                          ),
                          PopupMenuItem(
                            value: 'reports',
                            child: Text('Отчёты'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (searching)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Название задачи или код проекта',
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                ),
              Expanded(
                child: expanded && !searching
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 8,
                            child: RefreshIndicator(
                              onRefresh: store.refresh,
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  40,
                                  4,
                                  32,
                                  28,
                                ),
                                children: [todaySection()],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: Container(
                              decoration: BoxDecoration(
                                color: colors.surface,
                                border: Border(
                                  left: BorderSide(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                              ),
                              child: RefreshIndicator(
                                onRefresh: store.refresh,
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    32,
                                    4,
                                    40,
                                    28,
                                  ),
                                  children: [sideSections()],
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : RefreshIndicator(
                        onRefresh: store.refresh,
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 88),
                          children: [
                            if (searching) ...[
                              if (matches.isEmpty)
                                const EmptyState(
                                  icon: Symbols.search_sharp,
                                  title: 'Задачи не найдены',
                                )
                              else
                                rows(matches),
                            ] else ...[
                              todaySection(),
                              sideSections(),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
          floatingActionButton: expanded
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => showTaskEditor(context, store),
                  icon: const Icon(Symbols.add_sharp),
                  label: const Text('Задача'),
                ),
        );
      },
    ),
  );
}

class _ProjectStatusBar extends StatelessWidget {
  final List<TaskoTask> tasks;
  const _ProjectStatusBar({required this.tasks});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (tasks.isEmpty) {
      return Container(height: 4, color: colors.surfaceContainerHighest);
    }
    return Row(
      children: [
        for (final status in const [
          TaskStatus.done,
          TaskStatus.review,
          TaskStatus.inProgress,
          TaskStatus.blocked,
          TaskStatus.todo,
        ])
          if (tasks.any((t) => t.status == status))
            Expanded(
              flex: tasks.where((t) => t.status == status).length,
              child: Container(
                height: 4,
                margin: const EdgeInsets.only(right: 2),
                color: status == TaskStatus.todo
                    ? colors.surfaceContainerHighest
                    : _statusColor(context, status),
              ),
            ),
      ],
    );
  }
}

class _CoreTaskRow extends StatelessWidget {
  final TaskoTask task;
  final TaskoStore store;
  final VoidCallback onTap;
  final bool statusMetadata;
  const _CoreTaskRow({
    required this.task,
    required this.store,
    required this.onTap,
    this.statusMetadata = true,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      final project = _project(store, task.projectId);
      final id = taskReference(task, project);
      final done = task.status == TaskStatus.done;
      final wide =
          constraints.maxWidth > 600 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.2;
      final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.2;
      Widget checkbox = SizedBox(
        width: 48,
        height: 48,
        child: Checkbox(
          value: done,
          semanticLabel: 'Завершить: ${task.title}',
          onChanged: (_) async {
            try {
              await store.moveTask(
                task.id,
                done ? TaskStatus.todo : TaskStatus.done,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    done ? 'Задача → К выполнению' : 'Задача → Готово',
                  ),
                  action: SnackBarAction(
                    label: 'Отмена',
                    onPressed: () async {
                      try {
                        await store.moveTask(task.id, task.status);
                      } catch (e) {
                        if (context.mounted) _error(context, e);
                      }
                    },
                  ),
                ),
              );
            } catch (e) {
              if (context.mounted) _error(context, e);
            }
          },
        ),
      );
      final priority = Icon(
        _priorityIcon(task.priority),
        size: 16,
        color: task.priority == TaskPriority.urgent
            ? colors.error
            : colors.onSurfaceVariant,
      );
      final date = Text(
        dateLabel(task.dueDate),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'JetBrains Mono',
          color: task.overdue(DateTime.now())
              ? colors.error
              : colors.onSurfaceVariant,
        ),
      );
      return Material(
        color: _card(context),
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            padding: EdgeInsets.fromLTRB(
              0,
              wide ? 0 : 8,
              statusMetadata || wide ? 16 : 0,
              wide ? 0 : 8,
            ),
            child: Row(
              children: [
                checkbox,
                if (wide) ...[
                  SizedBox(
                    width: 88,
                    child: Text(
                      id,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontFamily: 'JetBrains Mono'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        key: ValueKey('task-title-${task.id}'),
                        maxLines: statusMetadata || largeText ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (wide
                                    ? Theme.of(context).textTheme.bodyMedium
                                    : Theme.of(context).textTheme.bodyLarge)
                                ?.copyWith(
                                  height: !wide && !statusMetadata
                                      ? 20 / 15
                                      : null,
                                  color: done
                                      ? colors.onSurfaceVariant
                                      : colors.onSurface,
                                ),
                      ),
                      if (!wide) ...[
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: statusMetadata ? 8 : 10,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              id,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontFamily: 'JetBrains Mono',
                                    color: colors.onSurfaceVariant,
                                  ),
                            ),
                            if (statusMetadata)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _statusIcon(task.status),
                                    size: 16,
                                    color: _statusColor(context, task.status),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    task.status.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: _statusColor(
                                            context,
                                            task.status,
                                          ),
                                        ),
                                  ),
                                ],
                              )
                            else
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  priority,
                                  const SizedBox(width: 3),
                                  Text(
                                    task.priority.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            date,
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (wide || statusMetadata) const SizedBox(width: 8),
                if (wide) ...[
                  SizedBox(
                    width: 132,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusChip(status: task.status),
                    ),
                  ),
                  const SizedBox(width: 8),
                  priority,
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 64,
                    child: Align(alignment: Alignment.centerRight, child: date),
                  ),
                ] else if (statusMetadata)
                  priority
                else
                  SizedBox(
                    width: 40,
                    child: Center(
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: colors.secondaryContainer,
                        foregroundColor: colors.onSecondaryContainer,
                        child: Text(
                          project?.teamId == null
                              ? store.profile.initials
                              : '—',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ProjectsScreen extends StatefulWidget {
  final TaskoStore store;
  final ValueChanged<String>? onOpenProject;
  const ProjectsScreen({super.key, required this.store, this.onOpenProject});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String query = '';
  bool archived = false;
  bool searching = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final projects = store.projects
          .where(
            (project) =>
                project.archived == archived &&
                '${project.name} ${project.key}'.toLowerCase().contains(
                  query.toLowerCase(),
                ),
          )
          .toList();
      final colors = Theme.of(context).colorScheme;
      return Scaffold(
        body: Column(
          children: [
            _PageHeader(
              'Проекты',
              actions: [
                IconButton(
                  tooltip: 'Поиск проектов',
                  onPressed: () => setState(() => searching = !searching),
                  icon: const Icon(Symbols.search_sharp),
                ),
                IconButton.filled(
                  tooltip: 'Создать проект',
                  onPressed: () => showProjectEditor(context, store),
                  icon: Icon(Symbols.add_sharp, color: colors.onPrimary),
                ),
              ],
            ),
            Container(
              color: colors.surface,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  if (searching)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Название или код проекта',
                          prefixIcon: Icon(Symbols.search_sharp),
                        ),
                        onChanged: (value) => setState(() => query = value),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(
                            'Активные · ${store.projects.where((p) => !p.archived).length}',
                          ),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(
                            'Архив · ${store.projects.where((p) => p.archived).length}',
                          ),
                        ),
                      ],
                      selected: {archived},
                      onSelectionChanged: (value) =>
                          setState(() => archived = value.first),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: store.refresh,
                child: projects.isEmpty
                    ? ListView(
                        children: [
                          EmptyState(
                            icon: Symbols.folder_open_sharp,
                            title: query.isEmpty
                                ? (archived
                                      ? 'В архиве пока пусто'
                                      : 'Пока нет проектов')
                                : 'Проекты не найдены',
                            detail: query.isEmpty
                                ? 'Проект объединяет задачи, сроки и прогресс.'
                                : 'Попробуйте другое название или код.',
                            action: query.isEmpty && !archived
                                ? FilledButton(
                                    onPressed: () =>
                                        showProjectEditor(context, store),
                                    child: const Text('Создать проект'),
                                  )
                                : null,
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: projects.length,
                        itemBuilder: (context, index) => _ProjectRow(
                          project: projects[index],
                          store: store,
                          onOpen: widget.onOpenProject,
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ProjectRow extends StatelessWidget {
  final TaskoProject project;
  final TaskoStore store;
  final ValueChanged<String>? onOpen;
  const _ProjectRow({required this.project, required this.store, this.onOpen});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tasks = store.tasks
        .where((task) => task.projectId == project.id)
        .toList();
    final done = tasks.where((task) => task.status == TaskStatus.done).length;
    return Material(
      color: _card(context),
      child: InkWell(
        onTap: () => onOpen != null
            ? onOpen!(project.id)
            : Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      BoardScreen(store: store, projectId: project.id),
                ),
              ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              project.key,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontFamily: 'JetBrains Mono'),
                            ),
                            Text(
                              project.teamId == null
                                  ? store.profile.name
                                  : 'Командный проект',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        dateLabel(project.dueDate),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                      Text(
                        '$done из ${tasks.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ProjectStatusBar(tasks: tasks),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final status in const [
                    TaskStatus.done,
                    TaskStatus.review,
                    TaskStatus.inProgress,
                    TaskStatus.blocked,
                    TaskStatus.todo,
                  ])
                    if (tasks.any((t) => t.status == status))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _statusIcon(status),
                            size: 16,
                            color: _statusColor(context, status),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${tasks.where((t) => t.status == status).length}',
                            semanticsLabel:
                                '${status.label}: ${tasks.where((t) => t.status == status).length}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TasksScreen extends StatefulWidget {
  final TaskoStore store;
  final ValueChanged<String>? onTaskSelected;
  const TasksScreen({super.key, required this.store, this.onTaskSelected});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String query = '';
  String? projectId;
  TaskPriority? priority;
  bool searching = false, groupByProject = false, showCompleted = false;
  int dueFilter = 0;
  TaskStatus? statusFilter;
  TaskIssueType? typeFilter;
  String? labelFilter;
  TaskSort sort = TaskSort.queue;
  bool includeArchived = false, _viewBusy = false;
  List<TaskView> _views = [];
  String? _viewName;
  final _searchText = TextEditingController();
  int _viewLoadRevision = 0,
      _scopeRevision = 0,
      _queryRevision = 0,
      _viewOperationRevision = 0;
  String? _viewScope;
  int _viewSessionRevision = -1;
  final Set<Route<dynamic>> _scopeRoutes = {};
  final Set<String> collapsed = {TaskStatus.todo.db, TaskStatus.done.db};

  TaskQuery get _query => TaskQuery(
    text: query,
    projectId: projectId,
    priority: priority,
    status: statusFilter,
    issueType: typeFilter,
    label: labelFilter,
    dueFilter: dueFilter,
    sort: sort,
    includeArchived: includeArchived,
    showCompleted: showCompleted,
    groupByProject: groupByProject,
  );

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_scopeChanged);
    _scopeChanged();
  }

  @override
  void didUpdateWidget(covariant TasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_scopeChanged);
      widget.store.addListener(_scopeChanged);
      _viewSessionRevision = -1;
      _scopeChanged();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_scopeChanged);
    _viewLoadRevision++;
    _viewOperationRevision++;
    _searchText.dispose();
    super.dispose();
  }

  void _scopeChanged() {
    final scope = widget.store.preferenceScope;
    if (scope == _viewScope &&
        _viewSessionRevision == widget.store.sessionRevision) {
      return;
    }
    _viewScope = scope;
    _viewSessionRevision = widget.store.sessionRevision;
    for (final route in _scopeRoutes.toList()) {
      if (route.isActive) route.navigator?.removeRoute(route);
    }
    _scopeRoutes.clear();
    _scopeRevision++;
    _viewLoadRevision++;
    _viewOperationRevision++;
    setState(() {
      _views = [];
      _viewName = null;
      _viewBusy = false;
      _assignQuery(const TaskQuery());
      collapsed.addAll({TaskStatus.todo.db, TaskStatus.done.db});
    });
    _loadViews();
  }

  void _assignQuery(TaskQuery value, {String? name}) {
    _queryRevision++;
    query = value.text;
    _searchText.text = query;
    searching = query.isNotEmpty;
    projectId = value.projectId;
    priority = value.priority;
    dueFilter = value.dueFilter;
    statusFilter = value.status;
    typeFilter = value.issueType;
    labelFilter = value.label;
    sort = value.sort;
    includeArchived = value.includeArchived;
    showCompleted = value.showCompleted || value.status == TaskStatus.done;
    groupByProject = value.groupByProject;
    collapsed.clear();
    _viewName = name;
  }

  Future<void> _loadViews() async {
    final revision = ++_viewLoadRevision;
    final scope = widget.store.preferenceScope;
    if (scope == null) return;
    try {
      final views = await TaskViews(scope).load();
      if (mounted &&
          revision == _viewLoadRevision &&
          scope == widget.store.preferenceScope) {
        setState(() => _views = views);
      }
    } catch (_) {
      if (mounted && revision == _viewLoadRevision) {
        _error(context, StateError('Не удалось прочитать представления.'));
      }
    }
  }

  void _changeFilters(VoidCallback change) => setState(() {
    change();
    _queryRevision++;
    collapsed.clear();
    _viewName = null;
  });

  void _applyQuery(TaskQuery value, {String? name}) =>
      setState(() => _assignQuery(value, name: name));

  Future<void> _filters() async {
    final scope = widget.store.preferenceScope;
    final scopeRevision = _scopeRevision;
    final value = await showTaskFilters(
      context,
      _query,
      widget.store.tasks.expand((t) => t.labels).toSet().toList(),
      onRoute: _scopeRoutes.add,
    );
    _scopeRoutes.removeWhere((route) => !route.isActive);
    if (mounted &&
        value != null &&
        scope == widget.store.preferenceScope &&
        scopeRevision == _scopeRevision) {
      _applyQuery(value);
    }
  }

  Future<void> _saveView() async {
    if (_viewBusy) return;
    final scope = widget.store.preferenceScope;
    if (scope == null) return;
    final snapshot = _query;
    final queryRevision = _queryRevision;
    final scopeRevision = _scopeRevision;
    final input = TextEditingController();
    final form = GlobalKey<FormState>();
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сохранить представление'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: input,
            autofocus: true,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Название'),
            validator: (value) {
              final name = (value ?? '').trim();
              if (name.isEmpty) return 'Введите название';
              if (_views.any(
                (v) => normalizeTaskSearch(v.name) == normalizeTaskSearch(name),
              )) {
                return 'Такое название уже есть';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, input.text.trim());
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    _scopeRoutes.add(route);
    final name = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    _scopeRoutes.remove(route);
    input.dispose();
    if (!mounted ||
        name == null ||
        scope != widget.store.preferenceScope ||
        scopeRevision != _scopeRevision) {
      return;
    }
    final operation = ++_viewOperationRevision;
    setState(() => _viewBusy = true);
    _viewLoadRevision++;
    try {
      final views = await TaskViews(scope).save(name, snapshot);
      if (mounted &&
          scope == widget.store.preferenceScope &&
          scopeRevision == _scopeRevision &&
          operation == _viewOperationRevision) {
        setState(() {
          _views = views;
          _viewName = queryRevision == _queryRevision ? name : null;
        });
      }
    } catch (e) {
      if (mounted &&
          scope == widget.store.preferenceScope &&
          scopeRevision == _scopeRevision &&
          operation == _viewOperationRevision) {
        _error(context, e);
      }
    } finally {
      if (mounted && operation == _viewOperationRevision) {
        setState(() => _viewBusy = false);
      }
    }
  }

  Future<void> _deleteView(String id) async {
    final scope = widget.store.preferenceScope;
    if (scope == null || _viewBusy) return;
    final scopeRevision = _scopeRevision;
    final operation = ++_viewOperationRevision;
    setState(() => _viewBusy = true);
    _viewLoadRevision++;
    try {
      final views = await TaskViews(scope).delete(id);
      if (mounted &&
          scope == widget.store.preferenceScope &&
          scopeRevision == _scopeRevision &&
          operation == _viewOperationRevision) {
        setState(() {
          _views = views;
          if (!views.any((view) => view.name == _viewName)) _viewName = null;
        });
      }
    } catch (e) {
      if (mounted &&
          scope == widget.store.preferenceScope &&
          scopeRevision == _scopeRevision &&
          operation == _viewOperationRevision) {
        _error(context, e);
      }
    } finally {
      if (mounted && operation == _viewOperationRevision) {
        setState(() => _viewBusy = false);
      }
    }
  }

  Future<void> _chooseView() async {
    final scope = widget.store.preferenceScope;
    final scopeRevision = _scopeRevision;
    final route = ModalBottomSheetRoute<String>(
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Представления',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (_views.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Настройте фильтры и сохраните первое представление из меню списка.',
                  ),
                ),
              for (final view in _views)
                ListTile(
                  title: Text(view.name),
                  subtitle: Text(view.query.sort.label),
                  onTap: () => Navigator.pop(context, 'apply:${view.id}'),
                  trailing: IconButton(
                    tooltip: 'Удалить представление ${view.name}',
                    icon: const Icon(Symbols.delete_sharp),
                    onPressed: () =>
                        Navigator.pop(context, 'delete:${view.id}'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    _scopeRoutes.add(route);
    final action = await Navigator.of(context).push(route);
    await route.completed;
    _scopeRoutes.remove(route);
    if (!mounted ||
        action == null ||
        scope != widget.store.preferenceScope ||
        scopeRevision != _scopeRevision) {
      return;
    }
    final id = action.substring(action.indexOf(':') + 1);
    if (action.startsWith('delete:')) {
      await _deleteView(id);
      return;
    }
    for (final view in _views) {
      if (view.id == id) {
        _applyQuery(view.query, name: view.name);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final colors = Theme.of(context).colorScheme;
      final tasks = _query.apply(store.tasks, store.projects, DateTime.now());
      final hasFilter =
          query.trim().isNotEmpty ||
          projectId != null ||
          priority != null ||
          statusFilter != null ||
          typeFilter != null ||
          labelFilter != null ||
          dueFilter != 0;
      return Scaffold(
        body: Column(
          children: [
            Container(
              color: colors.surface,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Задачи',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Поиск задач',
                    onPressed: () => setState(() {
                      searching = !searching;
                      if (!searching) {
                        query = '';
                        _searchText.clear();
                        _viewName = null;
                        _queryRevision++;
                      }
                    }),
                    icon: const Icon(Symbols.search_sharp, size: 24),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Действия списка задач',
                    icon: const Icon(Symbols.more_vert_sharp, size: 24),
                    onSelected: (action) {
                      if (action == 'create') {
                        showTaskEditor(context, store, projectId: projectId);
                      }
                      if (action == 'completed') {
                        _changeFilters(() {
                          showCompleted = !showCompleted;
                          if (!showCompleted &&
                              statusFilter == TaskStatus.done) {
                            statusFilter = null;
                          }
                        });
                      }
                      if (action == 'reset') {
                        _applyQuery(const TaskQuery());
                      }
                      if (action == 'filters') _filters();
                      if (action == 'saveView') _saveView();
                      if (action == 'views') _chooseView();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'create',
                        child: Text('Добавить задачу'),
                      ),
                      PopupMenuItem(
                        value: 'completed',
                        child: Text(
                          showCompleted
                              ? 'Скрыть завершённые'
                              : 'Показать завершённые',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'reset',
                        child: Text('Сбросить фильтры'),
                      ),
                      const PopupMenuItem(
                        value: 'filters',
                        child: Text('Фильтры и сортировка'),
                      ),
                      PopupMenuItem(
                        value: 'saveView',
                        enabled: !_viewBusy && _views.length < 10,
                        child: const Text('Сохранить представление'),
                      ),
                      PopupMenuItem(
                        value: 'views',
                        enabled: !_viewBusy,
                        child: Text('Представления · ${_views.length}'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Column(
                children: [
                  if (searching)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _searchText,
                        maxLength: 500,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Ключ, название, описание, метка',
                          counterText: '',
                          prefixIcon: Icon(Symbols.search_sharp),
                        ),
                        onChanged: (value) =>
                            _changeFilters(() => query = value),
                      ),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Tooltip(
                          message: 'Личные и доступные командные задачи. Фильтрация по исполнителю появится после назначения участников.',
                          child: _TasksFilterLabel(
                            'Мои',
                            leading: Symbols.person_sharp,
                            dropdown: false,
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          initialValue: projectId ?? '',
                          onSelected: (value) => _changeFilters(
                            () => projectId = value.isEmpty ? null : value,
                          ),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: '',
                              child: Text('Все проекты'),
                            ),
                            ...store.projects.map(
                              (p) => PopupMenuItem(
                                value: p.id,
                                child: Text(p.name),
                              ),
                            ),
                          ],
                          child: _TasksFilterLabel(
                            'Проект: ${projectId == null ? 'все' : _project(store, projectId!)?.key ?? 'удалён'}',
                            active: projectId != null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<int>(
                          initialValue: priority?.index ?? -1,
                          onSelected: (value) => _changeFilters(
                            () => priority = value < 0
                                ? null
                                : TaskPriority.values[value],
                          ),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: -1,
                              child: Text('Любой приоритет'),
                            ),
                            ...TaskPriority.values.map(
                              (p) => PopupMenuItem(
                                value: p.index,
                                child: Text(p.label),
                              ),
                            ),
                          ],
                          child: _TasksFilterLabel(
                            priority?.label ?? 'Приоритет',
                            active: priority != null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<int>(
                          initialValue: dueFilter,
                          onSelected: (value) =>
                              _changeFilters(() => dueFilter = value),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 0, child: Text('Любой срок')),
                            PopupMenuItem(value: 1, child: Text('Просрочены')),
                            PopupMenuItem(value: 2, child: Text('Сегодня')),
                            PopupMenuItem(value: 3, child: Text('Без срока')),
                          ],
                          child: _TasksFilterLabel(
                            const [
                              'Срок',
                              'Просрочены',
                              'Сегодня',
                              'Без срока',
                            ][dueFilter],
                            active: dueFilter != 0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _filters,
                          child: _TasksFilterLabel(
                            [
                                  if (typeFilter != null) typeFilter!.label,
                                  if (statusFilter != null) statusFilter!.label,
                                  ?labelFilter,
                                  if (sort != TaskSort.queue) sort.label,
                                ].isEmpty
                                ? 'Ещё фильтры'
                                : 'Фильтры применены',
                            active:
                                typeFilter != null ||
                                statusFilter != null ||
                                labelFilter != null ||
                                sort != TaskSort.queue ||
                                includeArchived,
                            leading: Symbols.filter_list_sharp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Symbols.segment_sharp, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: PopupMenuButton<bool>(
                      onSelected: (value) =>
                          _changeFilters(() => groupByProject = value),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: false, child: Text('По статусу')),
                        PopupMenuItem(value: true, child: Text('По проекту')),
                      ],
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              groupByProject ? 'По проекту' : 'По статусу',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Symbols.arrow_drop_down_sharp, size: 18),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    '${tasks.length} задач',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (_viewName != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _viewName!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: store.refresh,
                child: ListView(
                  children: [
                    if (tasks.isEmpty)
                      EmptyState(
                        icon: Symbols.checklist_sharp,
                        title: hasFilter ? 'Нет совпадений' : 'Нет задач',
                        detail:
                            projectId != null &&
                                _project(store, projectId!) == null
                            ? 'Проект из представления удалён или недоступен. Сбросьте фильтры.'
                            : hasFilter
                            ? 'Измените условия или сбросьте фильтры.'
                            : 'Добавьте задачу или включите завершённые в фильтрах.',
                        action: FilledButton(
                          onPressed: hasFilter
                              ? () => _applyQuery(const TaskQuery())
                              : () => showTaskEditor(context, store),
                          child: Text(
                            hasFilter ? 'Сбросить фильтры' : 'Добавить задачу',
                          ),
                        ),
                      ),
                    for (final group
                        in groupByProject
                            ? store.projects
                                  .map(
                                    (p) => (
                                      p.id,
                                      p.name,
                                      Symbols.folder_sharp,
                                      colors.onSurfaceVariant,
                                      tasks
                                          .where((t) => t.projectId == p.id)
                                          .toList(),
                                    ),
                                  )
                                  .toList()
                            : const [
                                    TaskStatus.inProgress,
                                    TaskStatus.review,
                                    TaskStatus.blocked,
                                    TaskStatus.todo,
                                    TaskStatus.done,
                                  ]
                                  .map(
                                    (status) => (
                                      status.db,
                                      status.label,
                                      _statusIcon(status),
                                      _statusColor(context, status),
                                      tasks
                                          .where((t) => t.status == status)
                                          .toList(),
                                    ),
                                  )
                                  .toList())
                      if (group.$5.isNotEmpty) ...[
                        Material(
                          color: colors.surfaceContainerLow,
                          shape: Border(
                            bottom: BorderSide(color: colors.outlineVariant),
                          ),
                          child: InkWell(
                            key: ValueKey('task-group-${group.$1}'),
                            onTap: () => setState(
                              () => collapsed.contains(group.$1)
                                  ? collapsed.remove(group.$1)
                                  : collapsed.add(group.$1),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                              child: Row(
                                children: [
                                  Icon(group.$3, size: 16, color: group.$4),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      group.$2,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${group.$5.length}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    collapsed.contains(group.$1)
                                        ? Symbols.expand_more_sharp
                                        : Symbols.expand_less_sharp,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (!collapsed.contains(group.$1))
                          ...group.$5.map(
                            (task) => _CoreTaskRow(
                              task: task,
                              store: store,
                              statusMetadata: false,
                              onTap: () => widget.onTaskSelected != null
                                  ? widget.onTaskSelected!(task.id)
                                  : showTaskDetails(context, store, task: task),
                            ),
                          ),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _TasksFilterLabel extends StatelessWidget {
  final String label;
  final bool active, dropdown;
  final IconData? leading;
  const _TasksFilterLabel(
    this.label, {
    this.active = false,
    this.dropdown = true,
    this.leading,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: EdgeInsets.fromLTRB(
            leading == null ? 10 : 8,
            7,
            dropdown ? 6 : 10,
            7,
          ),
          decoration: BoxDecoration(
            color: active ? colors.primaryContainer : null,
            border: Border.all(
              color: active ? colors.primaryContainer : colors.outline,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                Icon(leading, size: 16),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: active ? colors.onPrimaryContainer : colors.onSurface,
                ),
              ),
              if (dropdown) ...[
                const SizedBox(width: 2),
                const Icon(Symbols.arrow_drop_down_sharp, size: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class BoardScreen extends StatefulWidget {
  final TaskoStore store;
  final String projectId;
  final VoidCallback? onBack;
  const BoardScreen({
    super.key,
    required this.store,
    required this.projectId,
    this.onBack,
  });
  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen>
    with SingleTickerProviderStateMixin {
  TaskPriority? priority;
  int view = 0;
  late final TabController _statusTabs;
  Timer? _hoverTimer;
  TaskStatus? _hoveredStatus;

  @override
  void initState() {
    super.initState();
    _statusTabs = TabController(length: TaskStatus.values.length, vsync: this);
  }

  void _cancelHover() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _hoveredStatus = null;
  }

  void _hoverStatus(TaskStatus status) {
    if (_hoveredStatus == status) return;
    _cancelHover();
    _hoveredStatus = status;
    _hoverTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _statusTabs.animateTo(status.index);
    });
  }

  @override
  void dispose() {
    _cancelHover();
    _statusTabs.dispose();
    super.dispose();
  }

  final Set<String> _moving = {};
  final Map<String, int> _moveGeneration = {};
  String? _selfHoverId;

  List<TaskoTask> _ordered(Iterable<TaskoTask> tasks) =>
      tasks.toList()..sort((a, b) {
        final rank = a.position.compareTo(b.position);
        if (rank != 0) return rank;
        final date = a.createdAt.compareTo(b.createdAt);
        return date != 0 ? date : a.id.compareTo(b.id);
      });

  List<TaskoTask> _fullColumn(TaskStatus status) => _ordered(
    widget.store.tasks.where(
      (task) => task.projectId == widget.projectId && task.status == status,
    ),
  );

  TaskoTask? _currentTask(String id) {
    for (final task in widget.store.tasks) {
      if (task.id == id && task.projectId == widget.projectId) return task;
    }
    return null;
  }

  bool _canPlace(TaskoTask task, TaskStatus status, {String? beforeTaskId}) {
    if (_moving.contains(task.id) ||
        task.id == beforeTaskId ||
        task.projectId != widget.projectId ||
        _currentTask(task.id) == null) {
      return false;
    }
    if (beforeTaskId == null) return true;
    final anchor = _currentTask(beforeTaskId);
    return anchor != null && anchor.status == status;
  }

  Future<void> _move(
    TaskoTask dragged,
    TaskStatus status, {
    String? beforeTaskId,
  }) async {
    _cancelHover();
    if (!_canPlace(dragged, status, beforeTaskId: beforeTaskId)) return;
    final task = _currentTask(dragged.id)!;
    final source = _fullColumn(task.status);
    final originalIndex = source.indexWhere((item) => item.id == task.id);
    final originalAnchor = originalIndex + 1 < source.length
        ? source[originalIndex + 1].id
        : null;
    if (task.status == status && originalAnchor == beforeTaskId) return;
    final generation = (_moveGeneration[task.id] ?? 0) + 1;
    _moveGeneration[task.id] = generation;
    final store = widget.store;
    final sessionRevision = store.sessionRevision;
    setState(() => _moving.add(task.id));
    try {
      await store.moveTask(task.id, status, beforeTaskId: beforeTaskId);
      if (!mounted ||
          widget.store != store ||
          store.sessionRevision != sessionRevision ||
          !store.isAuthenticated) {
        return;
      }
      final saved = _currentTask(task.id);
      if (saved == null) return;
      final expectedOrder = _fullColumn(status)
          .map((item) => item.id)
          .join('|');
      _statusTabs.animateTo(status.index);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            task.status == status
                ? 'Порядок задач изменён'
                : 'Задача → ${status.label}',
          ),
          action: SnackBarAction(
            label: 'Отмена',
            onPressed: () async {
              final latest = _currentTask(task.id);
              final valid =
                  widget.store == store &&
                  store.isAuthenticated &&
                  store.sessionRevision == sessionRevision &&
                  latest != null &&
                  latest.status == saved.status &&
                  latest.position == saved.position &&
                  _moveGeneration[task.id] == generation &&
                  _fullColumn(status).map((item) => item.id).join('|') ==
                      expectedOrder &&
                  !_moving.contains(task.id);
              final anchor = originalAnchor == null
                  ? null
                  : _currentTask(originalAnchor);
              if (!valid ||
                  (originalAnchor != null &&
                      (anchor == null || anchor.status != task.status))) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Задача или её очередь уже изменились. Отмена недоступна.',
                      ),
                    ),
                  );
                }
                return;
              }
              _moveGeneration[task.id] = generation + 1;
              if (mounted) setState(() => _moving.add(task.id));
              try {
                await widget.store.moveTask(
                  task.id,
                  task.status,
                  beforeTaskId: originalAnchor,
                );
                if (mounted) _statusTabs.animateTo(task.status.index);
              } catch (e) {
                if (mounted) _error(context, e);
              } finally {
                if (mounted) setState(() => _moving.remove(task.id));
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) _error(context, e);
    } finally {
      if (mounted) setState(() => _moving.remove(task.id));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final project = _project(widget.store, widget.projectId);
      if (project == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Проект')),
          body: const EmptyState(
            icon: Symbols.folder_off_sharp,
            title: 'Проект не найден',
            detail: 'Возможно, его уже удалили.',
          ),
        );
      }
      final tasks = _ordered(
        widget.store.tasks.where(
          (task) =>
              task.projectId == project.id &&
              (priority == null || task.priority == priority),
        ),
      );
      final colors = Theme.of(context).colorScheme;
      final expanded = MediaQuery.sizeOf(context).width > 840;
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !expanded,
          leading: !expanded && widget.onBack != null
              ? BackButton(onPressed: widget.onBack)
              : null,
          toolbarHeight:
              MediaQuery.textScalerOf(context).scale(expanded ? 60 : 40) + 24,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (expanded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text(
                        'Проекты',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const Icon(Symbols.chevron_right_sharp, size: 16),
                      Text(
                        project.key,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontFamily: 'JetBrains Mono'),
                      ),
                    ],
                  ),
                ),
              Text(
                project.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: expanded
                    ? Theme.of(context).textTheme.headlineMedium
                    : Theme.of(context).textTheme.titleLarge,
              ),
              if (!expanded)
                Text(
                  '${view == 0
                      ? 'Доска'
                      : view == 1
                      ? 'Список'
                      : 'Таймлайн'} · ${tasks.length} задач',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          actions: [
            if (!expanded)
              IconButton(
                tooltip: 'Добавить задачу',
                onPressed: () => showTaskEditor(
                  context,
                  widget.store,
                  projectId: project.id,
                ),
                icon: const Icon(Symbols.add_sharp),
              ),
            PopupMenuButton<int>(
              tooltip: 'Фильтр по приоритету',
              icon: Icon(
                Symbols.filter_list_sharp,
                color: priority == null ? null : colors.primary,
              ),
              onSelected: (value) => setState(
                () => priority = value < 0 ? null : TaskPriority.values[value],
              ),
              itemBuilder: (_) => [
                const PopupMenuItem(value: -1, child: Text('Любой приоритет')),
                ...TaskPriority.values.map(
                  (p) => PopupMenuItem(value: p.index, child: Text(p.label)),
                ),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: 'Действия проекта',
              onSelected: (action) async {
                if (const ['board', 'list', 'timeline'].contains(action)) {
                  setState(
                    () => view = const [
                      'board',
                      'list',
                      'timeline',
                    ].indexOf(action),
                  );
                  return;
                }
                if (action == 'archive') {
                  try {
                    await widget.store.setProjectArchived(
                      project.id,
                      !project.archived,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            project.archived
                                ? 'Проект восстановлен'
                                : 'Проект перемещён в архив',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) _error(context, e);
                  }
                  return;
                }
                if (action == 'edit') {
                  await showProjectEditor(
                    context,
                    widget.store,
                    project: project,
                  );
                  return;
                }
                if (action == 'delete') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Удалить проект?'),
                      content: const Text(
                        'Все задачи проекта также будут удалены.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Удалить'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  try {
                    await widget.store.deleteProject(project.id);
                    if (context.mounted && Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    if (context.mounted) _error(context, e);
                  }
                }
              },
              itemBuilder: (_) => [
                if (!expanded) ...[
                  const PopupMenuItem(value: 'board', child: Text('Доска')),
                  const PopupMenuItem(value: 'list', child: Text('Список')),
                  const PopupMenuItem(
                    value: 'timeline',
                    child: Text('Таймлайн'),
                  ),
                ],
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Редактировать проект'),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    project.archived ? 'Восстановить проект' : 'В архив',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Удалить проект'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (expanded)
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(
                    bottom: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: DefaultTabController(
                  length: 3,
                  initialIndex: view,
                  child: Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          onTap: (value) => setState(() => view = value),
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: const [
                            Tab(
                              height: 44,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Symbols.view_kanban_sharp, size: 20),
                                  SizedBox(width: 6),
                                  Text('Доска'),
                                ],
                              ),
                            ),
                            Tab(
                              height: 44,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Symbols.list_sharp, size: 20),
                                  SizedBox(width: 6),
                                  Text('Список'),
                                ],
                              ),
                            ),
                            Tab(
                              height: 44,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Symbols.view_timeline_sharp, size: 20),
                                  SizedBox(width: 6),
                                  Text('Таймлайн'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => showTaskEditor(
                          context,
                          widget.store,
                          projectId: project.id,
                        ),
                        icon: const Icon(Symbols.add_sharp, size: 20),
                        label: const Text('Задача'),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (view == 2) {
                    return TimelineScreen(
                      store: widget.store,
                      projectId: project.id,
                      embedded: true,
                    );
                  }
                  if (view == 1) {
                    return RefreshIndicator(
                      onRefresh: widget.store.refresh,
                      child: ListView(
                        children: [
                          if (tasks.isEmpty)
                            const EmptyState(
                              icon: Symbols.checklist_sharp,
                              title: 'Пока нет задач',
                            ),
                          ...tasks.map(
                            (task) => TaskRow(
                              task: task,
                              project: project,
                              onTap: () => showTaskDetails(
                                context,
                                widget.store,
                                task: task,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (expanded) {
                    final columnWidth = ((constraints.maxWidth - 64) / 5).clamp(
                      240.0,
                      420.0,
                    );
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final status in TaskStatus.values)
                              Container(
                                width: columnWidth,
                                margin: const EdgeInsets.only(right: 8),
                                child: _column(
                                  context,
                                  project,
                                  status,
                                  tasks,
                                  expanded: true,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      ColoredBox(
                        color: colors.surface,
                        child: TabBar(
                          controller: _statusTabs,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: [
                            for (final status in TaskStatus.values)
                              Tab(
                                child: DragTarget<TaskoTask>(
                                  key: ValueKey('board-status-${status.name}'),
                                  onWillAcceptWithDetails: (details) {
                                    if (!_canPlace(details.data, status)) {
                                      return false;
                                    }
                                    _hoverStatus(status);
                                    return true;
                                  },
                                  onLeave: (_) {
                                    if (_hoveredStatus == status) {
                                      _cancelHover();
                                    }
                                  },
                                  onAcceptWithDetails: (details) =>
                                      _move(details.data, status),
                                  builder: (context, candidates, rejected) =>
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        color: candidates.isNotEmpty
                                            ? colors.primaryContainer
                                            : null,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _statusIcon(status),
                                              size: 16,
                                              color: _statusColor(
                                                context,
                                                status,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(status.label),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${tasks.where((task) => task.status == status).length}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium,
                                            ),
                                          ],
                                        ),
                                      ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _statusTabs,
                          children: [
                            for (final status in TaskStatus.values)
                              _column(context, project, status, tasks),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget _column(
    BuildContext context,
    TaskoProject project,
    TaskStatus status,
    List<TaskoTask> tasks, {
    bool expanded = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final items = _ordered(tasks.where((task) => task.status == status));
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DragTarget<TaskoTask>(
      key: ValueKey('board-column-${status.name}'),
      onWillAcceptWithDetails: (details) =>
          _selfHoverId != details.data.id && _canPlace(details.data, status),
      onAcceptWithDetails: (details) => _move(
        details.data,
        status,
        beforeTaskId: _selfHoverId == details.data.id ? details.data.id : null,
      ),
      builder: (context, candidates, rejected) => Container(
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? colors.primaryContainer
              : dark
              ? colors.surfaceContainerLow
              : colors.surfaceContainer,
          borderRadius: expanded ? BorderRadius.circular(10) : null,
          border: expanded
              ? Border.all(
                  color: candidates.isNotEmpty
                      ? colors.primary
                      : colors.outlineVariant,
                )
              : null,
        ),
        child: Column(
          children: [
            if (expanded)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _statusIcon(status),
                      size: 16,
                      color: _statusColor(context, status),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        status.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text('${items.length}'),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: widget.store.refresh,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Icon(
                              _statusIcon(status),
                              color: colors.onSurfaceVariant,
                              size: 24,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Нет задач',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Перенесите сюда задачу\nили добавьте новую',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ...items.map(
                      (task) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DragTarget<TaskoTask>(
                          key: ValueKey('board-before-${task.id}'),
                          onWillAcceptWithDetails: (details) {
                            _selfHoverId = details.data.id == task.id
                                ? task.id
                                : null;
                            return _canPlace(
                              details.data,
                              status,
                              beforeTaskId: task.id,
                            );
                          },
                          onLeave: (_) {
                            if (_selfHoverId == task.id) _selfHoverId = null;
                          },
                          onAcceptWithDetails: (details) => _move(
                            details.data,
                            status,
                            beforeTaskId: task.id,
                          ),
                          builder: (context, candidates, rejected) =>
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: candidates.isEmpty
                                          ? Colors.transparent
                                          : colors.primary,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, cardConstraints) {
                                    final initials = project.teamId == null
                                        ? widget.store.profile.initials
                                        : '—';
                                    final feedback = Material(
                                      color: Colors.transparent,
                                      child: Transform.rotate(
                                        angle: 0.02618,
                                        child: Transform.scale(
                                          scale: 1.02,
                                          child: SizedBox(
                                            width: cardConstraints.maxWidth,
                                            child: _BoardCard(
                                              task: task,
                                              project: project,
                                              initials: initials,
                                              dragging: true,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                    final slot = Stack(
                                      children: [
                                        Opacity(
                                          opacity: 0,
                                          child: _BoardCard(
                                            task: task,
                                            project: project,
                                            initials: initials,
                                          ),
                                        ),
                                        Positioned.fill(
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: colors
                                                  .surfaceContainerHighest,
                                              border: Border.all(
                                                color: colors.primary,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                    final card = _BoardCard(
                                      task: task,
                                      project: project,
                                      initials: initials,
                                      saving: _moving.contains(task.id),
                                      onTap: () => showTaskDetails(
                                        context,
                                        widget.store,
                                        task: task,
                                      ),
                                    );
                                    return _BoardMouseDraggable(
                                      key: ValueKey(
                                        'board-mouse-drag-${task.id}',
                                      ),
                                      data: task,
                                      feedback: feedback,
                                      childWhenDragging: slot,
                                      maxSimultaneousDrags:
                                          _moving.contains(task.id) ? 0 : 1,
                                      onDragEnd: (_) {
                                        _selfHoverId = null;
                                        _cancelHover();
                                      },
                                      child: _BoardTouchDraggable(
                                        key: ValueKey('board-drag-${task.id}'),
                                        data: task,
                                        feedback: feedback,
                                        childWhenDragging: slot,
                                        maxSimultaneousDrags:
                                            _moving.contains(task.id) ? 0 : 1,
                                        onDragEnd: (_) {
                                          _selfHoverId = null;
                                          _cancelHover();
                                        },
                                        child: card,
                                      ),
                                    );
                                  },
                                ),
                              ),
                        ),
                      ),
                    ),
                    DragTarget<TaskoTask>(
                      key: ValueKey('board-append-${status.name}'),
                      onWillAcceptWithDetails: (details) =>
                          _canPlace(details.data, status),
                      onAcceptWithDetails: (details) =>
                          _move(details.data, status),
                      builder: (context, candidates, rejected) => Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: candidates.isEmpty
                                  ? Colors.transparent
                                  : colors.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        child: TextButton.icon(
                          onPressed: () => showTaskEditor(
                            context,
                            widget.store,
                            projectId: project.id,
                            initialStatus: status,
                          ),
                          icon: const Icon(Symbols.add_sharp, size: 20),
                          label: Text(
                            candidates.isEmpty
                                ? 'Добавить задачу'
                                : 'В конец колонки',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardMouseDraggable extends Draggable<TaskoTask> {
  const _BoardMouseDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.maxSimultaneousDrags,
    super.onDragEnd,
  });
  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => ImmediateMultiDragGestureRecognizer(
    supportedDevices: const {PointerDeviceKind.mouse},
    allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
  )..onStart = onStart;
}

class _BoardTouchDraggable extends LongPressDraggable<TaskoTask> {
  const _BoardTouchDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.maxSimultaneousDrags,
    super.onDragEnd,
  }) : super(delay: const Duration(milliseconds: 250));
  @override
  DelayedMultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => DelayedMultiDragGestureRecognizer(
    delay: const Duration(milliseconds: 250),
    supportedDevices: const {
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.unknown,
    },
  )..onStart = onStart;
}

class _BoardCard extends StatelessWidget {
  final TaskoTask task;
  final TaskoProject project;
  final String initials;
  final VoidCallback? onTap;
  final bool dragging, saving;
  const _BoardCard({
    required this.task,
    required this.project,
    required this.initials,
    this.onTap,
    this.dragging = false,
    this.saving = false,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final id = taskReference(task, project);
    return Semantics(
      label:
          '${task.issueType.label}: ${task.title}. ${task.status.label}. ${task.priority.label} приоритет',
      hint: 'Нажмите, чтобы открыть задачу, или удерживайте для перемещения',
      child: Container(
        decoration: BoxDecoration(
          color: _card(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: dragging ? colors.outline : colors.outlineVariant,
          ),
          boxShadow: dragging
              ? [
                  BoxShadow(
                    color: colors.shadow.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.5
                          : 0.18,
                    ),
                    offset: const Offset(0, 8),
                    blurRadius: 20,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Tooltip(
                        message: task.issueType.label,
                        child: Icon(
                          const [
                            Symbols.task_alt_sharp,
                            Symbols.bug_report_sharp,
                            Symbols.bookmark_sharp,
                          ][task.issueType.index],
                          size: 16,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          id,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                        ),
                      ),
                      if (saving)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              key: ValueKey('board-saving-${task.id}'),
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      Tooltip(
                        message: '${task.priority.label} приоритет',
                        child: Icon(
                          _priorityIcon(task.priority),
                          size: 16,
                          color: task.priority == TaskPriority.urgent
                              ? colors.error
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    task.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: task.status == TaskStatus.done
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            Icon(
                              Symbols.event_sharp,
                              size: 16,
                              color: task.overdue(DateTime.now())
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                            ),
                            Text(
                              dateLabel(task.dueDate),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontFamily: 'JetBrains Mono',
                                    color: task.overdue(DateTime.now())
                                        ? colors.error
                                        : colors.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: colors.secondaryContainer,
                        foregroundColor: colors.onSecondaryContainer,
                        child: Text(
                          initials,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                  if (task.status == TaskStatus.blocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Symbols.block_sharp,
                            size: 16,
                            color: colors.error,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              task.description.isEmpty
                                  ? 'Причина блокировки не указана'
                                  : task.description,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showProjectEditor(
  BuildContext context,
  TaskoStore store, {
  TaskoProject? project,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ProjectEditor(store: store, project: project),
);

Future<void> showTaskEditor(
  BuildContext context,
  TaskoStore store, {
  TaskoTask? task,
  String? projectId,
  TaskStatus initialStatus = TaskStatus.todo,
  DateTime? initialDueDate,
}) async {
  if (store.projects.isEmpty) {
    await showProjectEditor(context, store);
    if (!context.mounted || store.projects.isEmpty) return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TaskEditor(
      store: store,
      task: task,
      projectId: projectId,
      initialStatus: initialStatus,
      initialDueDate: initialDueDate,
    ),
  );
}

class _EditorFrame extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget action;
  const _EditorFrame({
    required this.title,
    required this.child,
    required this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Symbols.close_sharp),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  child,
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: action,
          ),
        ],
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field(this.label, this.child);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        child,
      ],
    ),
  );
}

class _DateField extends StatelessWidget {
  final DateTime? date;
  final ValueChanged<DateTime?> onChanged;
  const _DateField({required this.date, required this.onChanged});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          icon: const Icon(Symbols.event_sharp, size: 20),
          label: Text(date == null ? 'Выбрать дату' : dateLabel(date)),
          onPressed: () async {
            final now = DateTime.now();
            final earliest = DateTime(now.year - 10);
            final latest = DateTime(now.year + 20);
            final initial = date ?? now;
            final picked = await showDatePicker(
              context: context,
              initialDate: initial.isBefore(earliest)
                  ? earliest
                  : initial.isAfter(latest)
                  ? latest
                  : initial,
              firstDate: earliest,
              lastDate: latest,
            );
            if (picked != null) onChanged(picked);
          },
        ),
      ),
      if (date != null)
        IconButton(
          tooltip: 'Убрать срок',
          onPressed: () => onChanged(null),
          icon: const Icon(Symbols.close_sharp),
        ),
    ],
  );
}

class _ProjectEditor extends StatefulWidget {
  final TaskoStore store;
  final TaskoProject? project;
  const _ProjectEditor({required this.store, this.project});
  @override
  State<_ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends State<_ProjectEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, key, description;
  DateTime? dueDate;
  String? error;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.project?.name ?? '');
    key = TextEditingController(text: widget.project?.key ?? '');
    description = TextEditingController(
      text: widget.project?.description ?? '',
    );
    dueDate = widget.project?.dueDate;
  }

  @override
  void dispose() {
    name.dispose();
    key.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.project == null) {
        await widget.store.createProject(
          name: name.text.trim(),
          key: key.text.trim().toUpperCase(),
          description: description.text.trim(),
          dueDate: dueDate,
        );
      } else {
        await widget.store.updateProject(
          TaskoProject(
            id: widget.project!.id,
            teamId: widget.project!.teamId,
            name: name.text.trim(),
            key: key.text.trim().toUpperCase(),
            description: description.text.trim(),
            dueDate: dueDate,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _EditorFrame(
    title: widget.project == null ? 'Новый проект' : 'Редактировать проект',
    action: FilledButton.icon(
      onPressed: saving ? null : save,
      icon: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Symbols.check_sharp, size: 20),
      label: Text(
        saving
            ? 'Сохранение…'
            : widget.project == null
            ? 'Создать проект'
            : 'Сохранить',
      ),
    ),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            'Название',
            TextFormField(
              controller: name,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              enabled: !saving,
              decoration: const InputDecoration(
                hintText: 'Например, Редизайн сайта',
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Введите название проекта'
                  : null,
            ),
          ),
          _Field(
            'Код проекта',
            TextFormField(
              controller: key,
              maxLength: 10,
              textCapitalization: TextCapitalization.characters,
              enabled: !saving,
              decoration: const InputDecoration(hintText: 'Например, WEB'),
              validator: (value) {
                final input = (value ?? '').trim().toUpperCase();
                if (!RegExp(r'^[A-Z][A-Z0-9]{1,9}$').hasMatch(input)) {
                  return 'От 2 до 10 латинских букв и цифр';
                }
                if (widget.store.projects.any(
                  (p) =>
                      p.id != widget.project?.id &&
                      p.key.toUpperCase() == input,
                )) {
                  return 'Такой код уже используется';
                }
                return null;
              },
            ),
          ),
          _Field(
            'Описание',
            TextFormField(
              controller: description,
              minLines: 3,
              maxLines: 5,
              maxLength: 2000,
              enabled: !saving,
              decoration: const InputDecoration(
                hintText: 'Какой результат хотите получить?',
              ),
            ),
          ),
          _Field(
            'Срок проекта',
            _DateField(
              date: dueDate,
              onChanged: (value) => setState(() => dueDate = value),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}

class _TaskEditor extends StatefulWidget {
  final TaskoStore store;
  final TaskoTask? task;
  final String? projectId;
  final TaskStatus initialStatus;
  final DateTime? initialDueDate;
  const _TaskEditor({
    required this.store,
    this.task,
    this.projectId,
    required this.initialStatus,
    this.initialDueDate,
  });
  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, description;
  late String projectId;
  late TaskStatus status;
  late TaskPriority priority;
  late TaskIssueType issueType;
  DateTime? dueDate;
  String? error;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.task?.title ?? '');
    description = TextEditingController(text: widget.task?.description ?? '');
    projectId =
        widget.task?.projectId ??
        widget.projectId ??
        widget.store.projects.first.id;
    if (!widget.store.projects.any((p) => p.id == projectId)) {
      projectId = widget.store.projects.first.id;
    }
    status = widget.task?.status ?? widget.initialStatus;
    priority = widget.task?.priority ?? TaskPriority.medium;
    issueType = widget.task?.issueType ?? TaskIssueType.task;
    dueDate = widget.task?.dueDate ?? widget.initialDueDate;
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (!form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final store = widget.store;
    TaskoTask? previous;
    for (final task in store.tasks) {
      if (task.id == widget.task?.id) previous = task;
    }
    // The editor may be opened from a filtered list. Its undo anchor must come
    // from the complete source column, independent of the visible sort/filter.
    String? originalAnchor;
    if (previous != null) {
      final source =
          store.tasks
              .where(
                (task) =>
                    task.projectId == previous!.projectId &&
                    task.status == previous.status,
              )
              .toList()
            ..sort((a, b) {
              final rank = a.position.compareTo(b.position);
              if (rank != 0) return rank;
              final date = a.createdAt.compareTo(b.createdAt);
              return date != 0 ? date : a.id.compareTo(b.id);
            });
      final index = source.indexWhere((task) => task.id == previous!.id);
      if (index >= 0 && index + 1 < source.length) {
        originalAnchor = source[index + 1].id;
      }
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.task == null) {
        await widget.store.createTask(
          projectId: projectId,
          title: title.text.trim(),
          description: description.text.trim(),
          priority: priority,
          status: status,
          dueDate: dueDate,
          issueType: issueType,
        );
      } else {
        final task = widget.task!;
        await widget.store.updateTask(
          task.copyWith(
            projectId: projectId,
            title: title.text.trim(),
            description: description.text.trim(),
            status: status,
            priority: priority,
            issueType: issueType,
            dueDate: dueDate,
            createdAt: task.createdAt,
            completedAt: status == TaskStatus.done
                ? task.completedAt ?? DateTime.now()
                : null,
          ),
        );
      }
      if (mounted) {
        Navigator.pop(context);
        if (previous != null && previous.status != status) {
          _showStatusUndo(messenger, store, previous, originalAnchor);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '$e';
        });
      }
    }
  }

  void _showStatusUndo(
    ScaffoldMessengerState messenger,
    TaskoStore store,
    TaskoTask previous,
    String? originalAnchor,
  ) {
    TaskoTask? currentTask() {
      for (final task in store.tasks) {
        if (task.id == previous.id) return task;
      }
      return null;
    }

    final saved = currentTask();
    if (saved == null) return;
    final scope = store.preferenceScope;
    final demo = store.isDemo;
    final sessionRevision = store.sessionRevision;
    var stale = false;
    var used = false;
    bool unchanged() {
      final current = currentTask();
      return store.isAuthenticated &&
          store.sessionRevision == sessionRevision &&
          store.preferenceScope == scope &&
          store.isDemo == demo &&
          current != null &&
          _sameUndoTask(saved, current);
    }

    void observe() {
      // Remember intermediate changes too: moving away and back or signing in
      // again must not revive a snackbar belonging to an earlier action.
      if (!unchanged()) stale = true;
    }

    store.addListener(observe);
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('Задача → ${saved.status.label}'),
        action: SnackBarAction(
          label: 'Отмена',
          onPressed: () async {
            if (used) return;
            used = true;
            if (stale || !unchanged() || store.busy) {
              if (messenger.mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Задача уже изменена или сессия завершена. Отмена недоступна.',
                    ),
                  ),
                );
              }
              return;
            }
            String? validAnchor;
            for (final task in store.tasks) {
              if (task.id == originalAnchor &&
                  task.projectId == saved.projectId &&
                  task.status == previous.status) {
                validAnchor = task.id;
              }
            }
            try {
              await store.moveTask(
                previous.id,
                previous.status,
                beforeTaskId: validAnchor,
              );
            } catch (e) {
              if (messenger.mounted) {
                messenger.showSnackBar(SnackBar(content: Text('$e')));
              }
            }
          },
        ),
      ),
    );
    controller.closed.whenComplete(() => store.removeListener(observe));
  }

  bool _sameUndoTask(TaskoTask saved, TaskoTask current) {
    if (saved.projectId != current.projectId ||
        saved.status != current.status ||
        saved.position != current.position ||
        saved.title != current.title ||
        saved.description != current.description ||
        saved.priority != current.priority ||
        saved.issueType != current.issueType ||
        saved.issueNumber != current.issueNumber ||
        saved.dueDate != current.dueDate ||
        saved.completedAt != current.completedAt ||
        saved.createdAt != current.createdAt ||
        saved.labels.length != current.labels.length) {
      return false;
    }
    for (var index = 0; index < saved.labels.length; index++) {
      if (saved.labels[index] != current.labels[index]) return false;
    }
    return true;
  }

  Future<void> delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text(widget.task!.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.deleteTask(widget.task!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _EditorFrame(
    title: widget.task == null ? 'Новая задача' : 'Карточка задачи',
    action: FilledButton.icon(
      onPressed: saving ? null : save,
      icon: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Symbols.check_sharp, size: 20),
      label: Text(
        saving
            ? 'Сохранение…'
            : widget.task == null
            ? 'Создать задачу'
            : 'Сохранить',
      ),
    ),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            'Название задачи',
            TextFormField(
              controller: title,
              maxLength: 120,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              enabled: !saving,
              decoration: const InputDecoration(hintText: 'Что нужно сделать?'),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Введите название задачи'
                  : null,
            ),
          ),
          _Field(
            'Проект',
            DropdownButtonFormField<String>(
              initialValue: projectId,
              isExpanded: true,
              items: widget.store.projects
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) => setState(() => projectId = value!),
            ),
          ),
          _Field(
            'Тип задачи',
            DropdownButtonFormField<TaskIssueType>(
              initialValue: issueType,
              isExpanded: true,
              items: TaskIssueType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.label)),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) => setState(() => issueType = value!),
            ),
          ),
          _Field(
            'Статус',
            DropdownButtonFormField<TaskStatus>(
              initialValue: status,
              isExpanded: true,
              items: TaskStatus.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Row(
                        children: [
                          Icon(
                            _statusIcon(s),
                            size: 16,
                            color: _statusColor(context, s),
                          ),
                          const SizedBox(width: 8),
                          Text(s.label),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) => setState(() => status = value!),
            ),
          ),
          _Field(
            'Приоритет',
            DropdownButtonFormField<TaskPriority>(
              initialValue: priority,
              isExpanded: true,
              items: TaskPriority.values
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Row(
                        children: [
                          Icon(_priorityIcon(p), size: 16),
                          const SizedBox(width: 8),
                          Text(p.label),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) => setState(() => priority = value!),
            ),
          ),
          _Field(
            'Срок',
            _DateField(
              date: dueDate,
              onChanged: (value) => setState(() => dueDate = value),
            ),
          ),
          _Field(
            'Описание',
            TextFormField(
              controller: description,
              minLines: 3,
              maxLines: 8,
              maxLength: 4000,
              enabled: !saving,
              decoration: const InputDecoration(
                hintText: 'Контекст, детали и ожидаемый результат',
              ),
            ),
          ),
          if (widget.task != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Создана ${dateLabel(widget.task!.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),

          if (widget.task != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: saving ? null : delete,
                icon: Icon(
                  Symbols.delete_outline_sharp,
                  color: Theme.of(context).colorScheme.error,
                ),
                label: Text(
                  'Удалить задачу',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
