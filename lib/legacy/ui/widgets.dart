import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../data/task_query.dart';
import '../theme.dart';

String dateLabel(DateTime? value) =>
    value == null ? 'Без срока' : DateFormat('d MMM', 'ru').format(value);

String taskReference(TaskoTask task, TaskoProject? project) =>
    taskKey(task, project);

class StatusChip extends StatelessWidget {
  final TaskStatus status;
  const StatusChip({super.key, required this.status});
  @override
  Widget build(BuildContext context) {
    final p = StatusPalette.of(status, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            p.icon,
            size: 16,
            weight: 300,
            fill: status == TaskStatus.done ? 1 : 0,
            color: p.foreground,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status.label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: p.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeading(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?trailing,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(
            detail!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

class TaskRow extends StatelessWidget {
  final TaskoTask task;
  final TaskoProject? project;
  final VoidCallback? onTap;
  const TaskRow({super.key, required this.task, this.project, this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = task.status == TaskStatus.done;
    return Material(
      color: TaskoColors.card(context),
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  done
                      ? Icons.check_circle_outline_sharp
                      : Icons.radio_button_unchecked_sharp,
                  size: 20,
                  color: done ? cs.primary : cs.outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: done ? cs.onSurfaceVariant : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          taskReference(task, project),
                          style: monoStyle(context),
                        ),
                        StatusChip(status: task.status),
                        Text(
                          dateLabel(task.dueDate),
                          style: monoStyle(
                            context,
                            color: task.overdue(DateTime.now())
                                ? cs.error
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
