import '../models.dart';

enum TaskSort { queue, dueDate, priority, newest }

extension TaskSortLabel on TaskSort {
  String get label =>
      ['По очереди', 'По сроку', 'По приоритету', 'Сначала новые'][index];
}

String normalizeTaskSearch(String text) =>
    text.trim().toLowerCase().replaceAll('ё', 'е');

String taskKey(TaskoTask task, TaskoProject? project) {
  final prefix = project?.key ?? 'TASK';
  if (task.issueNumber != null) return '$prefix-${task.issueNumber}';
  if (task.id.startsWith('$prefix-')) return task.id;
  return '$prefix-${task.id.length > 5 ? task.id.substring(0, 5).toUpperCase() : task.id}';
}

/// Basic structured search: AND between filters and between search words.
/// It deliberately does not parse or claim to implement Jira's JQL.
class TaskQuery {
  final String text;
  final String? projectId, label;
  final TaskPriority? priority;
  final TaskStatus? status;
  final TaskIssueType? issueType;
  final int dueFilter;
  final bool showCompleted, includeArchived, groupByProject;
  final TaskSort sort;
  const TaskQuery({
    this.text = '',
    this.projectId,
    this.label,
    this.priority,
    this.status,
    this.issueType,
    this.dueFilter = 0,
    this.showCompleted = false,
    this.includeArchived = false,
    this.groupByProject = false,
    this.sort = TaskSort.queue,
  });

  List<TaskoTask> apply(
    Iterable<TaskoTask> tasks,
    Iterable<TaskoProject> projects,
    DateTime now,
  ) {
    final byId = {for (final project in projects) project.id: project};
    final words = normalizeTaskSearch(text)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final result = tasks.where((task) {
      final project = byId[task.projectId];
      if (project == null || (!includeArchived && project.archived)) {
        return false;
      }
      if (!showCompleted &&
          status != TaskStatus.done &&
          task.status == TaskStatus.done) {
        return false;
      }
      if (projectId != null && task.projectId != projectId) return false;
      if (priority != null && task.priority != priority) return false;
      if (status != null && task.status != status) return false;
      if (issueType != null && task.issueType != issueType) return false;
      if (label != null &&
          !task.labels.any(
            (v) => normalizeTaskSearch(v) == normalizeTaskSearch(label!),
          )) {
        return false;
      }
      if (dueFilter == 1 && !task.overdue(now)) return false;
      if (dueFilter == 2 &&
          (task.dueDate == null || !_sameDay(task.dueDate!, now))) {
        return false;
      }
      if (dueFilter == 3 && task.dueDate != null) return false;
      final searchable = normalizeTaskSearch(
        [
          taskKey(task, project),
          task.id,
          task.title,
          task.description,
          ...task.labels,
          project.key,
          project.name,
        ].join(' '),
      );
      return words.every(searchable.contains);
    }).toList();
    result.sort((a, b) {
      int primary;
      switch (sort) {
        case TaskSort.queue:
          primary = byId[a.projectId]!.key.compareTo(byId[b.projectId]!.key);
          if (primary == 0) primary = a.status.index.compareTo(b.status.index);
          if (primary == 0) primary = a.position.compareTo(b.position);
        case TaskSort.dueDate:
          primary = a.dueDate == null
              ? (b.dueDate == null ? 0 : 1)
              : b.dueDate == null
              ? -1
              : a.dueDate!.compareTo(b.dueDate!);
        case TaskSort.priority:
          primary = b.priority.index.compareTo(a.priority.index);
        case TaskSort.newest:
          primary = b.createdAt.compareTo(a.createdAt);
      }
      if (primary != 0) return primary;
      final created = a.createdAt.compareTo(b.createdAt);
      return created != 0 ? created : a.id.compareTo(b.id);
    });
    return result;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Map<String, dynamic> toJson() => {
    'text': text,
    'projectId': projectId,
    'label': label,
    'priority': priority?.name,
    'status': status?.name,
    'issueType': issueType?.name,
    'dueFilter': dueFilter,
    'showCompleted': showCompleted,
    'includeArchived': includeArchived,
    'groupByProject': groupByProject,
    'sort': sort.name,
  };

  factory TaskQuery.fromJson(Map<String, dynamic> value) {
    T? enumValue<T extends Enum>(List<T> items, dynamic raw) {
      if (raw == null) return null;
      return items.firstWhere((v) => v.name == raw);
    }

    final due = value['dueFilter'] as int? ?? 0;
    if (due < 0 || due > 3) throw const FormatException('Unknown date filter');
    final text = value['text'] as String? ?? '';
    final label = value['label'] as String?;
    if (text.length > 500 || (label?.length ?? 0) > 24) {
      throw const FormatException('Invalid query');
    }
    return TaskQuery(
      text: text,
      projectId: value['projectId'] as String?,
      label: label,
      priority: enumValue(TaskPriority.values, value['priority']),
      status: enumValue(TaskStatus.values, value['status']),
      issueType: enumValue(TaskIssueType.values, value['issueType']),
      dueFilter: due,
      showCompleted: value['showCompleted'] as bool? ?? false,
      includeArchived: value['includeArchived'] as bool? ?? false,
      groupByProject: value['groupByProject'] as bool? ?? false,
      sort: enumValue(TaskSort.values, value['sort']) ?? TaskSort.queue,
    );
  }
}
