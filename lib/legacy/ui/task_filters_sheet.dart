import 'package:flutter/material.dart';

import '../data/task_query.dart';
import '../models.dart';

Future<TaskQuery?> showTaskFilters(
  BuildContext context,
  TaskQuery initial,
  List<String> labels, {
  ValueChanged<Route<dynamic>>? onRoute,
}) {
  final navigator = Navigator.of(context);
  final route = ModalBottomSheetRoute<TaskQuery>(
    isScrollControlled: true,
    useSafeArea: true,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    builder: (_) => _TaskFiltersSheet(initial: initial, labels: labels),
  );
  onRoute?.call(route);
  return navigator.push(route);
}

class _TaskFiltersSheet extends StatefulWidget {
  final TaskQuery initial;
  final List<String> labels;
  const _TaskFiltersSheet({required this.initial, required this.labels});
  @override
  State<_TaskFiltersSheet> createState() => _TaskFiltersSheetState();
}

class _TaskFiltersSheetState extends State<_TaskFiltersSheet> {
  late TaskStatus? status = widget.initial.status;
  late TaskIssueType? type = widget.initial.issueType;
  late String? label = widget.initial.label;
  late TaskSort sort = widget.initial.sort;
  late bool archived = widget.initial.includeArchived;
  late bool completed =
      widget.initial.showCompleted || widget.initial.status == TaskStatus.done;
  @override
  Widget build(BuildContext context) {
    final labels = {...widget.labels, ?label}.toList()..sort();
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final viewport = constraints.maxHeight;
        final available = (viewport - keyboard).clamp(0.0, viewport);
        final height = available.clamp(0.0, viewport * 0.88);
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SizedBox(
            height: height,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Фильтры и сортировка',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_sharp),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('task-filters-scroll'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: status?.index ?? -1,
                          decoration: const InputDecoration(
                            labelText: 'Статус',
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                              value: -1,
                              child: Text('Все статусы'),
                            ),
                            for (final item in TaskStatus.values)
                              DropdownMenuItem(
                                value: item.index,
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(() {
                            status = value == null || value < 0
                                ? null
                                : TaskStatus.values[value];
                            if (status == TaskStatus.done) completed = true;
                          }),
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<int>(
                          initialValue: type?.index ?? -1,
                          decoration: const InputDecoration(
                            labelText: 'Тип задачи',
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                              value: -1,
                              child: Text('Все типы'),
                            ),
                            for (final item in TaskIssueType.values)
                              DropdownMenuItem(
                                value: item.index,
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => type = value == null || value < 0
                                ? null
                                : TaskIssueType.values[value],
                          ),
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          initialValue: label ?? '',
                          decoration: const InputDecoration(labelText: 'Метка'),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Все метки'),
                            ),
                            for (final item in labels)
                              DropdownMenuItem(
                                value: item,
                                child: Text(
                                  item,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => label = value == null || value.isEmpty
                                ? null
                                : value,
                          ),
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<TaskSort>(
                          initialValue: sort,
                          decoration: const InputDecoration(
                            labelText: 'Сортировка',
                          ),
                          isExpanded: true,
                          items: [
                            for (final item in TaskSort.values)
                              DropdownMenuItem(
                                value: item,
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => sort = value ?? TaskSort.queue),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Завершённые задачи'),
                          value: completed,
                          onChanged: (value) => setState(() {
                            completed = value;
                            if (!value && status == TaskStatus.done) {
                              status = null;
                            }
                          }),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Архивные проекты'),
                          value: archived,
                          onChanged: (value) =>
                              setState(() => archived = value),
                        ),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        TaskQuery(
                          text: widget.initial.text,
                          projectId: widget.initial.projectId,
                          priority: widget.initial.priority,
                          dueFilter: widget.initial.dueFilter,
                          groupByProject: widget.initial.groupByProject,
                          status: status,
                          issueType: type,
                          label: label,
                          sort: sort,
                          includeArchived: archived,
                          showCompleted: completed,
                        ),
                      ),
                      key: const ValueKey('task-filters-apply'),
                      child: const Text('Применить'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
