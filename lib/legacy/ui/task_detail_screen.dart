import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/tasko_store.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Screen 06 from Tasko v2: a task document, with properties and conversation.
/// All identifiers and counters come from the repository, including demo mode.
class TaskDetailScreen extends StatefulWidget {
  final TaskoStore store;
  final String taskId;
  final Future<void> Function(BuildContext, TaskoTask) onEdit;
  final bool embedded;
  final VoidCallback? onClose;
  final ValueChanged<String>? onTaskCopied;
  const TaskDetailScreen({
    super.key,
    required this.store,
    required this.taskId,
    required this.onEdit,
    this.embedded = false,
    this.onClose,
    this.onTaskCopied,
  });

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen>
    with SingleTickerProviderStateMixin {
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();
  late final TabController _tabs;
  bool _loading = true;
  bool _saving = false;
  bool _duplicating = false;
  bool _hideCompleted = false;
  String? _detailError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_tabChanged);
    _queueLoad();
  }

  void _tabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant TaskDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId || oldWidget.store != widget.store) {
      _comment.clear();
      _tabs.index = 0;
      _loading = true;
      _detailError = null;
      _hideCompleted = false;
      _queueLoad();
    }
  }

  void _queueLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final taskId = widget.taskId;
    try {
      await widget.store.loadTaskDetails(taskId);
      if (mounted && widget.taskId == taskId) {
        setState(() => _detailError = null);
      }
    } catch (_) {
      if (mounted && widget.taskId == taskId) {
        setState(
          () => _detailError = 'Не удалось загрузить подзадачи и обсуждение.',
        );
      }
    } finally {
      if (mounted && widget.taskId == taskId) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    _comment.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  TaskoTask? get _task {
    for (final task in widget.store.tasks) {
      if (task.id == widget.taskId) return task;
    }
    return null;
  }

  TaskoProject? _project(TaskoTask task) {
    for (final project in widget.store.projects) {
      if (project.id == task.projectId) return project;
    }
    return null;
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      await action();
      if (mounted && widget.store.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.store.error!)));
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.store.error ??
                  'Не удалось сохранить изменение. Повторите попытку.',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _edit() async {
    final task = _task;
    if (task != null) await widget.onEdit(context, task);
  }

  Future<void> _delete() async {
    final task = _task;
    if (task == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text(
          '«${task.title}», подзадачи и комментарии будут удалены. Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final deleted = await _run(() => widget.store.deleteTask(task.id));
    if (deleted && mounted && widget.taskId == task.id) _close();
  }

  Future<void> _pickDate(TaskoTask task) async {
    final now = DateTime.now();
    final first = DateTime(2000);
    final last = DateTime(2100, 12, 31);
    var initial = task.dueDate ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Срок задачи',
    );
    if (date == null || !mounted) return;
    final current = _task;
    if (current != null && current.id == task.id) {
      await _run(
        () => widget.store.updateTask(current.copyWith(dueDate: date)),
      );
    }
  }

  Future<void> _editLabels(TaskoTask task) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: 'Метки задачи',
        label: 'Метки через запятую',
        initial: task.labels.join(', '),
        helper: 'До 5 меток, по 24 символа',
        saveLabel: 'Сохранить',
        validator: (value) {
          final labels = value
              .split(',')
              .map((label) => label.trim())
              .where((label) => label.isNotEmpty)
              .toSet();
          if (labels.length > 5) return 'Можно добавить не больше 5 меток';
          if (labels.any((label) => label.length > 24)) {
            return 'Метка: максимум 24 символа';
          }
          return null;
        },
      ),
    );
    if (value == null || !mounted) return;
    final labels = value
        .split(',')
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toSet()
        .toList();
    await _run(() => widget.store.setTaskLabels(task.id, labels));
  }

  Future<void> _addSubtask() async {
    final taskId = widget.taskId;
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: 'Добавить подзадачу',
        label: 'Название',
        maxLength: 120,
        saveLabel: 'Добавить',
        validator: (value) =>
            value.trim().isEmpty ? 'Введите название подзадачи' : null,
      ),
    );
    if (title == null || !mounted) return;
    await _run(() => widget.store.addSubtask(taskId, title.trim()));
  }

  Future<void> _renameSubtask(TaskoSubtask subtask) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: 'Редактировать подзадачу',
        label: 'Название',
        initial: subtask.title,
        maxLength: 120,
        saveLabel: 'Сохранить',
        validator: (value) => value.trim().isEmpty
            ? 'Введите название подзадачи'
            : value.trim().length > 120
            ? 'Максимум 120 символов'
            : null,
      ),
    );
    if (title == null || !mounted || title.trim() == subtask.title) return;
    await _run(() => widget.store.updateSubtask(subtask.id, title.trim()));
  }

  Future<void> _duplicate() async {
    final source = _task;
    if (source == null || _duplicating || _saving || widget.store.busy) return;
    final store = widget.store;
    setState(() => _duplicating = true);
    try {
      final options = await showDialog<_CopyOptions>(
        context: context,
        builder: (_) => _CopyTaskDialog(source: source),
      );
      if (options == null || !mounted) return;
      TaskoTask? copy;
      final success = await _run(() async {
        copy = await store.duplicateTask(
          source.id,
          title: options.title,
          includeSubtasks: options.includeSubtasks,
          copyDueDate: options.copyDueDate,
        );
      });
      if (!success || copy == null || !mounted || widget.store != store) return;
      final saved = copy!;
      if (widget.taskId == source.id) {
        _openCopy(saved);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Копия создана'),
            action: SnackBarAction(
              label: 'Открыть',
              onPressed: () {
                if (mounted) _openCopy(saved);
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _duplicating = false);
    }
  }

  void _openCopy(TaskoTask copy) {
    if (widget.onTaskCopied != null) {
      widget.onTaskCopied!(copy.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskDetailScreen(
          store: widget.store,
          taskId: copy.id,
          onEdit: widget.onEdit,
        ),
      ),
    );
  }

  Future<void> _sendComment() async {
    final taskId = widget.taskId;
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    if (text.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Комментарий: максимум 2000 символов')),
      );
      return;
    }
    final sent = await _run(() => widget.store.addComment(taskId, text));
    if (sent && mounted && widget.taskId == taskId) {
      _comment.clear();
      _commentFocus.unfocus();
      _tabs.index = 0;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final task = _task;
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final busy = _saving || _duplicating || widget.store.busy;
      return Scaffold(
        backgroundColor: colors.surface,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          toolbarHeight: 56,
          automaticallyImplyLeading: !widget.embedded,
          leading: widget.embedded
              ? null
              : IconButton(
                  tooltip: 'Назад',
                  onPressed: _close,
                  icon: const Icon(Symbols.arrow_back_sharp),
                ),
          titleSpacing: widget.embedded ? 24 : 0,
          title: Text(
            task == null ? widget.taskId : taskReference(task, _project(task)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(
              context,
              size: 12,
            ).copyWith(fontWeight: FontWeight.w500),
          ),
          actions: [
            IconButton(
              tooltip: 'Скопировать ID задачи',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.taskId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ID задачи скопирован')),
                  );
                }
              },
              icon: const Icon(Symbols.link_sharp, size: 24, weight: 300),
            ),
            PopupMenuButton<String>(
              tooltip: 'Действия с задачей',
              enabled: task != null && !busy,
              icon: const Icon(Symbols.more_vert_sharp, size: 24, weight: 300),
              onSelected: (value) {
                if (value == 'edit') {
                  _edit();
                } else if (value == 'delete') {
                  _delete();
                } else if (value == 'duplicate') {
                  _duplicate();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Редактировать'),
                ),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Создать копию'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Удалить задачу',
                    style: TextStyle(color: colors.error),
                  ),
                ),
              ],
            ),
            if (widget.embedded)
              IconButton(
                tooltip: 'Закрыть задачу',
                onPressed: _close,
                icon: const Icon(Symbols.close_sharp, size: 20, weight: 300),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: colors.outlineVariant),
          ),
        ),
        body: task == null
            ? const EmptyState(
                icon: Symbols.task_alt_sharp,
                title: 'Задача недоступна',
                detail: 'Она удалена либо у вас нет доступа к проекту.',
              )
            : SafeArea(
                top: false,
                bottom: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView(
                            key: const ValueKey('task-detail-content'),
                            padding: widget.embedded
                                ? const EdgeInsets.fromLTRB(8, 8, 8, 0)
                                : EdgeInsets.zero,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            children: _content(context, task, busy),
                          ),
                        ),
                        _composer(context, busy),
                      ],
                    ),
                  ),
                ),
              ),
      );
    },
  );

  List<Widget> _content(BuildContext context, TaskoTask task, bool busy) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final project = _project(task);
    final subtasks = widget.store.subtasks
        .where((subtask) => subtask.taskId == task.id)
        .toList();
    final visibleSubtasks = _hideCompleted
        ? subtasks.where((subtask) => !subtask.done).toList()
        : subtasks;
    final comments =
        widget.store.comments
            .where((comment) => comment.taskId == task.id)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final activities =
        widget.store.activities
            .where((activity) => activity.taskId == task.id)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              project?.name ?? 'Проект недоступен',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              task.title,
              style: widget.embedded
                  ? theme.textTheme.headlineMedium
                  : theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            if (!widget.embedded)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _statusControl(context, task, busy),
                  _priorityControl(context, task, busy),
                ],
              ),
          ],
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: TaskoColors.card(context),
          border: Border.symmetric(
            horizontal: BorderSide(color: colors.outlineVariant),
          ),
        ),
        child: Column(
          children: [
            _PropertyRow(
              label: 'Тип',
              child: PopupMenuButton<TaskIssueType>(
                tooltip: 'Изменить тип задачи',
                enabled: !busy,
                onSelected: (type) => _run(
                  () => widget.store.updateTask(task.copyWith(issueType: type)),
                ),
                itemBuilder: (_) => [
                  for (final type in TaskIssueType.values)
                    PopupMenuItem(value: type, child: Text(type.label)),
                ],
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Icon(
                        _issueIcon(task.issueType),
                        size: 16,
                        weight: 300,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          task.issueType.label,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const Icon(
                        Symbols.arrow_drop_down_sharp,
                        size: 16,
                        weight: 300,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.embedded)
              _PropertyRow(
                label: 'Статус',
                child: _statusControl(context, task, busy),
              ),
            _PropertyRow(
              label: 'Исполнитель',
              child: project != null && project.teamId == null
                  ? Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: colors.secondaryContainer,
                          child: Text(
                            widget.store.profile.initials,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSecondaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.store.profile.name,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    )
                  : Text('Не назначен', style: theme.textTheme.bodyMedium),
            ),
            _PropertyRow(
              label: 'Срок',
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: busy ? null : () => _pickDate(task),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            task.dueDate == null
                                ? 'Указать срок'
                                : DateFormat(
                                    'EEE, d MMM',
                                    'ru',
                                  ).format(task.dueDate!),
                            style: monoStyle(
                              context,
                              size: 12,
                              color: task.overdue(DateTime.now())
                                  ? colors.error
                                  : colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (task.dueDate != null)
                    IconButton(
                      tooltip: 'Убрать срок',
                      onPressed: busy
                          ? null
                          : () => _run(
                              () => widget.store.updateTask(
                                task.copyWith(dueDate: null),
                              ),
                            ),
                      icon: const Icon(
                        Symbols.close_sharp,
                        size: 16,
                        weight: 300,
                      ),
                    ),
                ],
              ),
            ),
            if (widget.embedded)
              _PropertyRow(
                label: 'Приоритет',
                child: _priorityControl(context, task, busy),
              ),
            _PropertyRow(
              label: 'Метки',
              divider: false,
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (task.labels.isEmpty)
                          Text(
                            'Нет меток',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        for (final label in task.labels)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              label,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Изменить метки',
                    onPressed: busy ? null : () => _editLabels(task),
                    icon: const Icon(Symbols.edit_sharp, size: 16, weight: 300),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  task.description.isEmpty
                      ? 'Добавьте описание задачи.'
                      : task.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: task.description.isEmpty
                        ? colors.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Изменить описание',
              onPressed: busy ? null : _edit,
              icon: const Icon(Symbols.edit_sharp, size: 16, weight: 300),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text('Подзадачи', style: theme.textTheme.titleLarge),
            ),
            Text(
              '${subtasks.where((subtask) => subtask.done).length}/${subtasks.length}',
              style: monoStyle(context),
            ),
            PopupMenuButton<bool>(
              tooltip: 'Настройки подзадач',
              enabled: !_loading,
              icon: const Icon(Symbols.more_horiz_sharp, size: 20, weight: 300),
              onSelected: (hide) => setState(() => _hideCompleted = hide),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: !_hideCompleted,
                  child: Text(
                    _hideCompleted
                        ? 'Показать выполненные'
                        : 'Скрыть выполненные',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text('Загружаем обсуждение…'),
        ),
      if (_detailError != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _detailError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.error,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: const Text('Повторить загрузку'),
              ),
            ],
          ),
        ),
      if (_hideCompleted && subtasks.isNotEmpty && visibleSubtasks.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Все подзадачи выполнены',
                style: theme.textTheme.bodyMedium,
              ),
              TextButton(
                onPressed: () => setState(() => _hideCompleted = false),
                child: const Text('Показать все'),
              ),
            ],
          ),
        ),
      if (visibleSubtasks.isNotEmpty)
        Container(
          decoration: BoxDecoration(
            color: TaskoColors.card(context),
            border: Border.symmetric(
              horizontal: BorderSide(color: colors.outlineVariant),
            ),
          ),
          child: Column(
            children: [
              for (final subtask in visibleSubtasks)
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 48,
                        child: Checkbox(
                          semanticLabel: subtask.title,
                          value: subtask.done,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          onChanged: busy
                              ? null
                              : (done) => _run(
                                  () => widget.store.setSubtaskDone(
                                    subtask.id,
                                    done!,
                                  ),
                                ),
                        ),
                      ),
                      Expanded(
                        child: Tooltip(
                          message: 'Редактировать подзадачу',
                          child: InkWell(
                            onTap: busy ? null : () => _renameSubtask(subtask),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                subtask.title,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: subtask.done
                                      ? colors.onSurfaceVariant
                                      : colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Удалить подзадачу ${subtask.title}',
                        onPressed: busy
                            ? null
                            : () => _run(
                                () => widget.store.deleteSubtask(subtask.id),
                              ),
                        icon: const Icon(
                          Symbols.close_sharp,
                          size: 16,
                          weight: 300,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : _addSubtask,
            icon: const Icon(Symbols.add_sharp, size: 20, weight: 300),
            label: const Text('Добавить подзадачу'),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Комментарии'),
                  const SizedBox(width: 6),
                  Text(
                    '${comments.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Tab(text: 'История'),
          ],
        ),
      ),
      if (_tabs.index == 0) ...[
        if (!_loading && _detailError == null && comments.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Комментариев пока нет. Напишите первый.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        for (final comment in comments)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AuthorAvatar(comment.authorName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            comment.authorName,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            _time(comment.createdAt),
                            style: monoStyle(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(comment.body, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ] else ...[
        if (!_loading && _detailError == null && activities.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Изменений пока нет.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        for (final activity in activities)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.history_sharp,
                  size: 16,
                  weight: 300,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${activity.actorName} · ${activity.body}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _time(activity.createdAt),
                        style: monoStyle(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      const SizedBox(height: 16),
    ];
  }

  Widget _statusControl(BuildContext context, TaskoTask task, bool busy) {
    final theme = Theme.of(context);
    final status = StatusPalette.of(task.status, theme.brightness);
    return PopupMenuButton<TaskStatus>(
      tooltip: 'Изменить статус',
      enabled: !busy,
      onSelected: (value) => _run(() => widget.store.moveTask(task.id, value)),
      itemBuilder: (_) => [
        for (final value in TaskStatus.values)
          PopupMenuItem(
            value: value,
            child: StatusChip(status: value),
          ),
      ],
      child: _ChipTarget(
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
          decoration: BoxDecoration(
            color: status.background,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                status.icon,
                size: 16,
                weight: 300,
                color: status.foreground,
                fill: task.status == TaskStatus.done ? 1 : 0,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  task.status.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: status.ink,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Symbols.arrow_drop_down_sharp,
                size: 16,
                color: status.ink,
                weight: 300,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priorityControl(BuildContext context, TaskoTask task, bool busy) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopupMenuButton<TaskPriority>(
      tooltip: 'Изменить приоритет',
      enabled: !busy,
      onSelected: (value) =>
          _run(() => widget.store.updateTask(task.copyWith(priority: value))),
      itemBuilder: (_) => [
        for (final value in TaskPriority.values)
          PopupMenuItem(value: value, child: Text(value.label)),
      ],
      child: _ChipTarget(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _priorityIcon(task.priority),
                size: 16,
                weight: 300,
                color: task.priority == TaskPriority.urgent
                    ? colors.error
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  task.priority.label,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer(BuildContext context, bool busy) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('task-comment-input'),
                  controller: _comment,
                  focusNode: _commentFocus,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  enabled: !busy && !_loading && _detailError == null,
                  style: Theme.of(context).textTheme.bodyMedium,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Комментарий',
                    counterText: '',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Отправить комментарий',
                onPressed:
                    busy ||
                        _loading ||
                        _detailError != null ||
                        _comment.text.trim().isEmpty
                    ? null
                    : _sendComment,
                icon: Icon(
                  Symbols.send_sharp,
                  size: 24,
                  weight: 300,
                  color: _comment.text.trim().isEmpty
                      ? colors.onSurfaceVariant
                      : colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _time(DateTime value) =>
      DateFormat('d MMM · HH:mm', 'ru').format(value.toLocal());
}

class _ChipTarget extends StatelessWidget {
  final Widget child;
  const _ChipTarget({required this.child});
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Align(alignment: Alignment.centerLeft, widthFactor: 1, child: child),
  );
}

class _PropertyRow extends StatelessWidget {
  final String label;
  final Widget child;
  final bool divider;
  const _PropertyRow({
    required this.label,
    required this.child,
    this.divider = true,
  });
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      border: divider
          ? Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            )
          : null,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 112,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _AuthorAvatar extends StatelessWidget {
  final String name;
  const _AuthorAvatar(this.name);
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 16,
    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
    child: Text(
      name
          .trim()
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .take(2)
          .map((part) => part[0])
          .join()
          .toUpperCase(),
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSecondaryContainer),
    ),
  );
}

IconData _priorityIcon(TaskPriority priority) => switch (priority) {
  TaskPriority.low => Symbols.signal_cellular_alt_1_bar_sharp,
  TaskPriority.medium => Symbols.signal_cellular_alt_2_bar_sharp,
  TaskPriority.high => Symbols.signal_cellular_alt_sharp,
  TaskPriority.urgent => Symbols.error_sharp,
};

IconData _issueIcon(TaskIssueType type) => switch (type) {
  TaskIssueType.task => Symbols.task_alt_sharp,
  TaskIssueType.bug => Symbols.bug_report_sharp,
  TaskIssueType.story => Symbols.auto_stories_sharp,
};

class _CopyOptions {
  final String title;
  final bool includeSubtasks, copyDueDate;
  const _CopyOptions(this.title, this.includeSubtasks, this.copyDueDate);
}

class _CopyTaskDialog extends StatefulWidget {
  final TaskoTask source;
  const _CopyTaskDialog({required this.source});
  @override
  State<_CopyTaskDialog> createState() => _CopyTaskDialogState();
}

class _CopyTaskDialogState extends State<_CopyTaskDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  bool _includeSubtasks = true, _copyDueDate = false, _submitted = false;
  @override
  void initState() {
    super.initState();
    const suffix = ' — копия';
    final buffer = StringBuffer();
    var length = 0;
    for (final character in widget.source.title.characters) {
      if (length + character.length > 120 - suffix.length) break;
      buffer.write(character);
      length += character.length;
    }
    _title = TextEditingController(
      text: '${buffer.toString().trimRight()}$suffix',
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Создать копию задачи'),
    content: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Название', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('task-copy-title'),
            controller: _title,
            maxLength: 120,
            minLines: 1,
            maxLines: 3,
            enabled: !_submitted,
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Введите название задачи'
                : value!.trim().length > 120
                ? 'Максимум 120 символов'
                : null,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Копировать подзадачи'),
            value: _includeSubtasks,
            onChanged: _submitted
                ? null
                : (value) => setState(() => _includeSubtasks = value!),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Сохранить срок'),
            value: _copyDueDate,
            onChanged: _submitted || widget.source.dueDate == null
                ? null
                : (value) => setState(() => _copyDueDate = value!),
          ),
          const SizedBox(height: 12),
          Text(
            'Новая задача начнётся со статуса «К выполнению». Отметки подзадач сбросятся. Комментарии и прежняя история не копируются.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitted ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _submitted
            ? null
            : () {
                if (_form.currentState!.validate()) {
                  setState(() => _submitted = true);
                  Navigator.pop(
                    context,
                    _CopyOptions(
                      _title.text.trim(),
                      _includeSubtasks,
                      _copyDueDate,
                    ),
                  );
                }
              },
        child: const Text('Создать копию'),
      ),
    ],
  );
}

class _TextDialog extends StatefulWidget {
  final String title, label, initial, saveLabel;
  final String? helper;
  final int? maxLength;
  final String? Function(String) validator;
  const _TextDialog({
    required this.title,
    required this.label,
    required this.saveLabel,
    required this.validator,
    this.initial = '',
    this.helper,
    this.maxLength,
  });
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextFormField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            maxLength: widget.maxLength,
            decoration: InputDecoration(helperText: widget.helper),
            validator: (value) => widget.validator(value ?? ''),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _controller.text);
          }
        },
        child: Text(widget.saveLabel),
      ),
    ],
  );
}
