enum TaskStatus { todo, inProgress, review, blocked, done }

enum TaskPriority { low, medium, high, urgent }

enum TaskIssueType { task, bug, story }

extension TaskIssueTypeLabel on TaskIssueType {
  String get label => ['Задача', 'Ошибка', 'История'][index];
}

extension TaskStatusLabel on TaskStatus {
  String get label => [
    'К выполнению',
    'В работе',
    'На ревью',
    'Заблокировано',
    'Готово',
  ][index];
  String get db => ['todo', 'in_progress', 'review', 'blocked', 'done'][index];
}

extension TaskPriorityLabel on TaskPriority {
  String get label => ['Низкий', 'Средний', 'Высокий', 'Срочный'][index];
}

class TaskoProject {
  final String id, name, key, description;
  final String? teamId;
  final DateTime? dueDate;
  final bool archived;
  const TaskoProject({
    required this.id,
    required this.name,
    required this.key,
    this.description = '',
    this.teamId,
    this.dueDate,
    this.archived = false,
  });
  static const _unchanged = Object();
  TaskoProject copyWith({
    String? id,
    String? name,
    String? key,
    String? description,
    String? teamId,
    bool? archived,
    Object? dueDate = _unchanged,
  }) => TaskoProject(
    id: id ?? this.id,
    name: name ?? this.name,
    key: key ?? this.key,
    description: description ?? this.description,
    teamId: teamId ?? this.teamId,
    archived: archived ?? this.archived,
    dueDate: identical(dueDate, _unchanged)
        ? this.dueDate
        : dueDate as DateTime?,
  );
}

class TaskoTask {
  final String id, projectId, title, description;
  final TaskStatus status;
  final TaskPriority priority;
  final DateTime? dueDate, completedAt;
  final DateTime createdAt;
  final List<String> labels;
  final TaskIssueType issueType;
  final int? issueNumber;
  final int position;
  const TaskoTask({
    required this.id,
    required this.projectId,
    required this.title,
    this.description = '',
    this.status = TaskStatus.todo,
    this.priority = TaskPriority.medium,
    this.dueDate,
    this.completedAt,
    required this.createdAt,
    this.labels = const [],
    this.issueType = TaskIssueType.task,
    this.issueNumber,
    this.position = 0,
  });
  static const _unchanged = Object();
  TaskoTask copyWith({
    String? id,
    String? projectId,
    String? title,
    String? description,
    TaskStatus? status,
    TaskPriority? priority,
    DateTime? createdAt,
    Object? dueDate = _unchanged,
    Object? completedAt = _unchanged,
    List<String>? labels,
    TaskIssueType? issueType,
    Object? issueNumber = _unchanged,
    int? position,
  }) => TaskoTask(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    createdAt: createdAt ?? this.createdAt,
    dueDate: identical(dueDate, _unchanged)
        ? this.dueDate
        : dueDate as DateTime?,
    completedAt: identical(completedAt, _unchanged)
        ? this.completedAt
        : completedAt as DateTime?,
    labels: labels ?? this.labels,
    issueType: issueType ?? this.issueType,
    issueNumber: identical(issueNumber, _unchanged)
        ? this.issueNumber
        : issueNumber as int?,
    position: position ?? this.position,
  );
  bool overdue(DateTime now) =>
      status != TaskStatus.done &&
      dueDate != null &&
      dueDate!.isBefore(DateTime(now.year, now.month, now.day));
}

class TaskoSubtask {
  final String id, taskId, title;
  final bool done;
  final DateTime createdAt;
  const TaskoSubtask({
    required this.id,
    required this.taskId,
    required this.title,
    this.done = false,
    required this.createdAt,
  });
}

class TaskoComment {
  final String id, taskId, authorName, body;
  final DateTime createdAt;
  const TaskoComment({
    required this.id,
    required this.taskId,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });
}

class TaskoActivity {
  final String id, taskId, actorName, body;
  final DateTime createdAt;
  const TaskoActivity({
    required this.id,
    required this.taskId,
    required this.actorName,
    required this.body,
    required this.createdAt,
  });
}

class TaskoProfile {
  final String name, email, role;
  const TaskoProfile({
    this.name = 'Мария Соколова',
    this.email = 'maria@tasko.local',
    this.role = 'Продуктовый дизайнер',
  });
  String get initials => name
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((s) => s.isEmpty ? '' : s[0])
      .join()
      .toUpperCase();
}
