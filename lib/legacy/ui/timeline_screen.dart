import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/tasko_store.dart';
import '../models.dart';
import '../theme.dart';
import 'task_routes.dart';
import 'widgets.dart';

/// Project dates plotted from actual creation dates to actual deadlines.
class TimelineScreen extends StatefulWidget {
  final TaskoStore store;
  final String projectId;
  final bool embedded;
  const TimelineScreen({
    super.key,
    required this.store,
    required this.projectId,
    this.embedded = false,
  });
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  bool month = false;
  late DateTime anchor = DateTime.now();
  DateTime day(DateTime date) => DateTime(date.year, date.month, date.day);
  void shift(int direction) => setState(() {
    anchor = month
        ? DateTime(anchor.year, anchor.month + direction, 1)
        : anchor.add(Duration(days: direction * 14));
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final text = Theme.of(context).textTheme;
      final project = widget.store.projects
          .where((p) => p.id == widget.projectId)
          .firstOrNull;
      final tasks =
          widget.store.tasks
              .where((t) => t.projectId == widget.projectId)
              .toList()
            ..sort(
              (a, b) => (a.dueDate ?? DateTime(9999)).compareTo(
                b.dueDate ?? DateTime(9999),
              ),
            );
      final dated = tasks.where((t) => t.dueDate != null).toList();
      final start = month
          ? DateTime(anchor.year, anchor.month, 1)
          : day(anchor).subtract(Duration(days: anchor.weekday - 1));
      final count = month ? DateTime(anchor.year, anchor.month + 1, 0).day : 14;
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final rowHeight = math.max(60.0, 52 * scale);
      final dayWidth =
          (MediaQuery.sizeOf(context).width < 600 ? 24.0 : 32.0) * scale;
      final headerHeight = 40.0 * scale;
      final tableWidth = count * dayWidth;
      final todayIndex = day(DateTime.now()).difference(start).inDays;
      Widget content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: colors.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.embedded)
                    Text('Таймлайн', style: text.headlineMedium),
                  Text(project?.name ?? 'Проект', style: text.titleSmall),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('2 недели')),
                      ButtonSegment(value: true, label: Text('Месяц')),
                    ],
                    selected: {month},
                    onSelectionChanged: (value) =>
                        setState(() => month = value.single),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('LLLL yyyy', 'ru').format(start),
                          style: text.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Предыдущий период',
                        onPressed: () => shift(-1),
                        icon: const Icon(Symbols.chevron_left_sharp),
                      ),
                      IconButton(
                        tooltip: 'Сегодня',
                        onPressed: () =>
                            setState(() => anchor = DateTime.now()),
                        icon: const Icon(Symbols.today_sharp),
                      ),
                      IconButton(
                        tooltip: 'Следующий период',
                        onPressed: () => shift(1),
                        icon: const Icon(Symbols.chevron_right_sharp),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: dated.isEmpty
                ? EmptyState(
                    icon: Symbols.view_timeline_sharp,
                    title: 'Добавьте сроки задачам',
                    detail: 'Задачи со сроком появятся на временной шкале.',
                  )
                : SingleChildScrollView(
                    child: SizedBox(
                      height: headerHeight + rowHeight * dated.length,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: MediaQuery.sizeOf(context).width < 600
                                ? 114
                                : 220,
                            child: Column(
                              children: [
                                Container(
                                  height: headerHeight,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: colors.outlineVariant,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'Задача',
                                    style: text.labelMedium,
                                  ),
                                ),
                                for (final task in dated)
                                  InkWell(
                                    onTap: () => showTaskDetails(
                                      context,
                                      widget.store,
                                      task: task,
                                    ),
                                    child: Container(
                                      height: rowHeight,
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: colors.outlineVariant,
                                          ),
                                          right: BorderSide(
                                            color: colors.outlineVariant,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            taskReference(task, project),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: monoStyle(context),
                                          ),
                                          Text(
                                            task.title,
                                            style: text.bodySmall,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: tableWidth,
                                child: Stack(
                                  children: [
                                    Column(
                                      children: [
                                        Row(
                                          children: [
                                            for (var i = 0; i < count; i++)
                                              Container(
                                                width: dayWidth,
                                                height: headerHeight,
                                                decoration: BoxDecoration(
                                                  color: i == todayIndex
                                                      ? colors.primaryContainer
                                                      : colors.surface,
                                                  border: Border(
                                                    bottom: BorderSide(
                                                      color:
                                                          colors.outlineVariant,
                                                    ),
                                                  ),
                                                ),
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      DateFormat(
                                                        'EE',
                                                        'ru',
                                                      ).format(
                                                        start.add(
                                                          Duration(days: i),
                                                        ),
                                                      ),
                                                      style: text.labelSmall,
                                                    ),
                                                    Text(
                                                      '${start.add(Duration(days: i)).day}',
                                                      style: text.labelMedium,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                        for (final task in dated)
                                          _TimelineBar(
                                            task: task,
                                            start: start,
                                            count: count,
                                            dayWidth: dayWidth,
                                            height: rowHeight,
                                            onTap: () => showTaskDetails(
                                              context,
                                              widget.store,
                                              task: task,
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (todayIndex >= 0 && todayIndex < count)
                                      Positioned(
                                        top: headerHeight,
                                        bottom: 0,
                                        left: todayIndex * dayWidth,
                                        child: IgnorePointer(
                                          child: Container(
                                            width: 2,
                                            color: colors.primary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'От создания до срока · ${tasks.length - dated.length} без срока',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ),
        ],
      );
      if (widget.embedded) return content;
      return Scaffold(
        backgroundColor: colors.surfaceContainerLowest,
        appBar: AppBar(title: const Text('Таймлайн')),
        body: content,
      );
    },
  );
}

class _TimelineBar extends StatelessWidget {
  final TaskoTask task;
  final DateTime start;
  final int count;
  final double dayWidth, height;
  final VoidCallback onTap;
  const _TimelineBar({
    required this.task,
    required this.start,
    required this.count,
    required this.dayWidth,
    required this.height,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final end = DateTime(
      task.dueDate!.year,
      task.dueDate!.month,
      task.dueDate!.day,
    );
    final created = DateTime(
      task.createdAt.year,
      task.createdAt.month,
      task.createdAt.day,
    );
    final begin = created.isAfter(end) ? end : created;
    final left = math.max(0, begin.difference(start).inDays);
    final right = math.min(count, end.difference(start).inDays + 1);
    final status = StatusPalette.of(task.status, Theme.of(context).brightness);
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Stack(
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: i * dayWidth,
              top: 0,
              bottom: 0,
              child: Container(
                width: dayWidth,
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: .5),
                    ),
                  ),
                ),
              ),
            ),
          if (right > left)
            Positioned(
              left: left * dayWidth + 2,
              width: (right - left) * dayWidth - 4,
              top: (height - 28) / 2,
              height: 28,
              child: Tooltip(
                message: '${task.title} · ${dateLabel(task.dueDate)}',
                child: Material(
                  color: status.background,
                  borderRadius: BorderRadius.circular(4),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          status.icon,
                          size: 16,
                          color: status.foreground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
