import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'student_models.dart';
import 'student_kanban.dart';
import 'student_formatters.dart';
export 'student_formatters.dart';
import 'student_store.dart';
import 'student_theme.dart';
import 'student_widgets.dart';
import 'student_assignment_screens.dart';

class StudyAssignmentTile extends StatelessWidget {
  const StudyAssignmentTile({
    super.key,
    required this.store,
    required this.assignment,
    this.highlight = false,
    this.onTap,
    this.statusAction = true,
  });
  final StudentStore store;
  final StudyAssignment assignment;
  final bool highlight;
  final VoidCallback? onTap;
  final bool statusAction;
  @override
  Widget build(BuildContext context) {
    final subject = store.subjectById(assignment.subjectId);
    final overdue =
        assignment.status != StudyStatus.done &&
        assignment.dueAt.isBefore(DateTime.now());
    return Semantics(
      button: true,
      label:
          '${assignment.title}, ${subject?.name ?? 'Без предмета'}, ${assignment.status.label}',
      child: Material(
        color: highlight
            ? StudentColors.cream.withValues(alpha: .58)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: StudentColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap:
              onTap ?? () => showStudyAssignment(context, store, assignment.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject?.name ?? 'Предмет удалён',
                  style: const TextStyle(
                    fontSize: 12,
                    color: StudentColors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  assignment.title,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        assignment.status == StudyStatus.done
                            ? 'Выполнено'
                            : '${overdue ? 'Просрочено · ' : ''}${studyDeadline(assignment.dueAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: assignment.status == StudyStatus.done
                              ? StudentColors.success
                              : overdue
                              ? StudentColors.danger
                              : StudentColors.muted,
                        ),
                      ),
                    ),
                    if (statusAction)
                      PopupMenuButton<StudyStatus>(
                        tooltip: 'Изменить статус ${assignment.title}',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 180),
                        onSelected: (status) => studentGuard(context, () async {
                          await store.setStatus(assignment.id, status);
                        }),
                        itemBuilder: (_) => StudyStatus.values
                            .map(
                              (s) =>
                                  PopupMenuItem(value: s, child: Text(s.label)),
                            )
                            .toList(),
                        icon: const StudentIcon('dots-three', size: 20),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StudentTodayScreen extends StatelessWidget {
  const StudentTodayScreen({
    super.key,
    required this.store,
    required this.onAssignments,
  });
  final StudentStore store;
  final VoidCallback onAssignments;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = store.classesForDay(now);
    final upcoming = store.classes.where((c) => c.endsAt.isAfter(now)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final next = upcoming.isEmpty ? null : upcoming.first;
    final active =
        store.assignments.where((a) => a.status != StudyStatus.done).toList()
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final ongoing = next != null && !next.startsAt.isAfter(now);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      children: [
        Text(
          '${store.profile.group.isEmpty ? 'МОЯ УЧЁБА' : store.profile.group.toUpperCase()} / УЧЕБНЫЙ СЕМЕСТР',
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: .6,
            color: StudentColors.muted,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '${now.day}',
              style: const TextStyle(
                fontSize: 56,
                height: 1.15,
                letterSpacing: -2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat(
                      'd MMMM',
                      'ru',
                    ).format(now).replaceFirst(RegExp(r'^\d+\s+'), ''),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    DateFormat('EEEE', 'ru').format(now),
                    style: const TextStyle(color: StudentColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '${today.length} ${_plural(today.length, 'пара', 'пары', 'пар')}  ·  ${active.length} ${_plural(active.length, 'задание', 'задания', 'заданий')}',
          style: const TextStyle(color: StudentColors.muted),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          ongoing ? 'Сейчас идёт пара' : 'Следующая пара',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 18),
        if (next == null)
          const Text(
            'Ближайших пар нет. Добавьте расписание во вкладке «Пары».',
            style: TextStyle(color: StudentColors.muted, height: 1.6),
          )
        else
          InkWell(
            onTap: () => showStudyClass(context, store, next.id),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 75,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studyTime(next.startsAt),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: StudentColors.accent,
                          ),
                        ),
                        Text(
                          studyTime(next.endsAt),
                          style: const TextStyle(
                            fontSize: 13,
                            color: StudentColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.subjectById(next.subjectId)?.name ?? next.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          next.title,
                          style: const TextStyle(color: StudentColors.muted),
                        ),
                        Text(
                          '${studyDate(next.startsAt)}${next.room.isEmpty ? '' : ' · ${next.room}'}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: StudentColors.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Посмотреть пару',
                          style: TextStyle(
                            color: StudentColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Ближайшие сроки',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: onAssignments,
              child: const Text('Все задания'),
            ),
          ],
        ),
        if (active.isEmpty)
          const StudentEmpty(
            title: 'Можно выдохнуть',
            message: 'Активных заданий пока нет. Добавьте первое задание и укажите срок сдачи.',
          )
        else
          ...active
              .take(3)
              .map(
                (a) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: StudyAssignmentTile(
                    store: store,
                    assignment: a,
                    highlight: a == active.first,
                    statusAction: false,
                  ),
                ),
              ),
        const SizedBox(height: 24),
        StudentButton(
          label: 'Добавить задание',
          icon: 'plus',
          outlined: true,
          onPressed: () => showCreateStudyAssignment(context, store),
        ),
      ],
    );
  }
}

String _plural(int count, String one, String few, String many) {
  final n = count % 100;
  if (n >= 11 && n <= 14) return many;
  return switch (count % 10) {
    1 => one,
    2 || 3 || 4 => few,
    _ => many,
  };
}

class StudentAssignmentsScreen extends StatefulWidget {
  const StudentAssignmentsScreen({
    super.key,
    required this.store,
    this.initialSubjectId,
    this.onInteractionChanged,
  });
  final StudentStore store;
  final String? initialSubjectId;
  final ValueChanged<bool>? onInteractionChanged;
  @override
  State<StudentAssignmentsScreen> createState() =>
      _StudentAssignmentsScreenState();
}

class _StudentAssignmentsScreenState extends State<StudentAssignmentsScreen> {
  bool _board = true, _searching = false, _interacting = false;
  final _search = TextEditingController();
  String? _subject;
  StudyStatus? _status;
  String _deadline = 'Все сроки';
  static const _deadlines = [
    'Все сроки',
    'Просроченные',
    'Сегодня',
    'На неделе',
  ];
  @override
  void initState() {
    super.initState();
    _subject = widget.initialSubjectId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _interaction(bool value) {
    if (!mounted) return;
    setState(() => _interacting = value);
    widget.onInteractionChanged?.call(value);
  }

  Future<void> _filters() async {
    var deadline = _deadline;
    var status = _status;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Фильтры',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setSheet(() {
                        deadline = _deadlines.first;
                        status = null;
                      }),
                      child: const Text('Сбросить'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const StudentFieldLabel('Срок сдачи'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in _deadlines)
                      ChoiceChip(
                        label: Text(value),
                        selected: deadline == value,
                        onSelected: (_) => setSheet(() => deadline = value),
                      ),
                  ],
                ),
                if (!_board) ...[
                  const SizedBox(height: 20),
                  const StudentFieldLabel('Статус'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Любой'),
                        selected: status == null,
                        onSelected: (_) => setSheet(() => status = null),
                      ),
                      for (final value in StudyStatus.values)
                        ChoiceChip(
                          label: Text(value.label),
                          selected: status == value,
                          onSelected: (_) => setSheet(() => status = value),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                StudentButton(
                  label: 'Показать задания',
                  onPressed: () {
                    setState(() {
                      _deadline = deadline;
                      _status = status;
                    });
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _matchesDeadline(StudyAssignment assignment) {
    final now = DateTime.now(), today = DateUtils.dateOnly(DateTime.now());
    switch (_deadline) {
      case 'Просроченные':
        return assignment.status != StudyStatus.done &&
            assignment.dueAt.isBefore(now);
      case 'Сегодня':
        return DateUtils.isSameDay(assignment.dueAt, today);
      case 'На неделе':
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return !assignment.dueAt.isBefore(monday) &&
            assignment.dueAt.isBefore(monday.add(const Duration(days: 7)));
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final subjectId = store.subjectById(_subject ?? '') == null
        ? null
        : _subject;
    final query = _search.text.trim().toLowerCase();
    final assignments =
        store.assignments
            .where(
              (a) =>
                  (subjectId == null || a.subjectId == subjectId) &&
                  (_board || _status == null || a.status == _status) &&
                  _matchesDeadline(a) &&
                  (a.title.toLowerCase().contains(query) ||
                      (store
                              .subjectById(a.subjectId)
                              ?.name
                              .toLowerCase()
                              .contains(query) ??
                          false)),
            )
            .toList()
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final filterCount =
        (_deadline != _deadlines.first ? 1 : 0) +
        (!_board && _status != null ? 1 : 0);
    Widget viewButton(String title, bool board) {
      final active = _board == board;
      return Semantics(
        selected: active,
        child: TextButton(
          onPressed: _interacting ? null : () => setState(() => _board = board),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            foregroundColor: active
                ? StudentColors.accent
                : StudentColors.muted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: StudentMotion.duration(context, StudentMotion.fast),
                height: 2,
                width: 22,
                decoration: BoxDecoration(
                  color: active ? StudentColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 51,
          child: ListView.separated(
            key: const PageStorageKey('assignment-subject-tabs'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: store.subjects.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 20),
            itemBuilder: (context, index) {
              final subject = index == 0 ? null : store.subjects[index - 1];
              final selected = subject?.id == subjectId;
              return Semantics(
                selected: selected,
                child: InkWell(
                  key: ValueKey('subject-tab-${subject?.id ?? 'all'}'),
                  onTap: _interacting
                      ? null
                      : () => setState(() => _subject = subject?.id),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 13),
                          child: Text(
                            subject?.name ?? 'Все предметы',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected
                                  ? StudentColors.ink
                                  : StudentColors.muted,
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: StudentMotion.duration(
                            context,
                            StudentMotion.fast,
                          ),
                          height: 3,
                          width: selected ? 26 : 0,
                          decoration: BoxDecoration(
                            color: StudentColors.accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 0),
          child: Row(
            children: [
              Flexible(flex: 2, child: viewButton('Канбан', true)),
              Flexible(flex: 2, child: viewButton('Список', false)),
              const Spacer(),
              IconButton(
                tooltip: _searching ? 'Закрыть поиск' : 'Поиск заданий',
                isSelected: _searching,
                onPressed: _interacting
                    ? null
                    : () => setState(() {
                        _searching = !_searching;
                        if (!_searching) {
                          _search.clear();
                          FocusScope.of(context).unfocus();
                        }
                      }),
                icon: Icon(_searching ? Icons.close : Icons.search, size: 22),
              ),
              IconButton(
                tooltip: 'Фильтры заданий',
                onPressed: _interacting ? null : _filters,
                icon: Badge(
                  isLabelVisible: filterCount > 0,
                  label: Text('$filterCount'),
                  child: const StudentIcon('sliders-horizontal', size: 22),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: StudentMotion.duration(context, StudentMotion.normal),
          alignment: Alignment.topCenter,
          child: _searching
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: TextField(
                    key: const ValueKey('assignments-search'),
                    controller: _search,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Название или предмет',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Очистить поиск',
                              onPressed: () => setState(_search.clear),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (filterCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              children: [
                if (_deadline != _deadlines.first)
                  InputChip(
                    label: Text(_deadline),
                    onDeleted: _interacting
                        ? null
                        : () => setState(() => _deadline = _deadlines.first),
                  ),
                if (!_board && _status != null)
                  InputChip(
                    label: Text(_status!.label),
                    onDeleted: () => setState(() => _status = null),
                  ),
              ],
            ),
          ),
        Expanded(
          child: IndexedStack(
            index: _board ? 0 : 1,
            children: [
              StudentKanban(
                store: store,
                assignments: assignments,
                onInteractionChanged: _interaction,
              ),
              assignments.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        StudentEmpty(
                          title: 'Заданий не найдено',
                          message: 'Измените предмет, поиск или фильтры.',
                          action: StudentButton(
                            label: 'Сбросить фильтры',
                            outlined: true,
                            onPressed: () => setState(() {
                              _subject = null;
                              _status = null;
                              _deadline = _deadlines.first;
                              _search.clear();
                            }),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      key: const PageStorageKey('assignments-list'),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: assignments.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => StudyAssignmentTile(
                        store: store,
                        assignment: assignments[i],
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class StudentScheduleScreen extends StatefulWidget {
  const StudentScheduleScreen({super.key, required this.store});
  final StudentStore store;
  @override
  State<StudentScheduleScreen> createState() => _StudentScheduleScreenState();
}

class _StudentScheduleScreenState extends State<StudentScheduleScreen> {
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  @override
  Widget build(BuildContext context) {
    final monday = _day.subtract(Duration(days: _day.weekday - 1)),
        classes = widget.store.classesForDay(_day);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Предыдущая неделя',
              onPressed: () =>
                  setState(() => _day = _day.subtract(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${studyDate(monday)} – ${studyDate(monday.add(const Duration(days: 6)))}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Следующая неделя',
              onPressed: () =>
                  setState(() => _day = _day.add(const Duration(days: 7))),
              icon: const StudentIcon('caret-right'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final date = monday.add(Duration(days: i)),
                  selected = DateUtils.isSameDay(date, _day);
              return SizedBox(
                width: (c.maxWidth - 24) / 7,
                child: Semantics(
                  selected: selected,
                  button: true,
                  label:
                      '${studyDate(date)}, ${DateFormat('EEEE', 'ru').format(date)}',
                  child: InkWell(
                    onTap: () => setState(() => _day = date),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? StudentColors.accent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            DateFormat('E', 'ru').format(date),
                            style: TextStyle(
                              fontSize: 11,
                              color: selected
                                  ? Colors.white
                                  : StudentColors.muted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : StudentColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          DateFormat('EEEE, d MMMM', 'ru').format(_day),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        if (classes.isEmpty)
          StudentEmpty(
            title: 'На этот день пар нет',
            message: 'Добавьте занятие или выберите другой день.',
            action: StudentButton(
              label: 'Добавить пару',
              icon: 'plus',
              onPressed: () =>
                  showStudyClassEditor(context, widget.store, date: _day),
            ),
          )
        else
          ...classes.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: InkWell(
                onTap: () => showStudyClass(context, widget.store, c.id),
                borderRadius: BorderRadius.circular(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 68,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            studyTime(c.startsAt),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            studyTime(c.endsAt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: StudentColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: c == classes.first
                              ? StudentColors.cream.withValues(alpha: .65)
                              : StudentColors.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.title,
                              style: const TextStyle(
                                fontSize: 12,
                                color: StudentColors.accent,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.store.subjectById(c.subjectId)?.name ??
                                  'Предмет',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              c.room.isEmpty ? 'Аудитория не указана' : c.room,
                              style: const TextStyle(
                                fontSize: 13,
                                color: StudentColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (classes.isNotEmpty) ...[
          const SizedBox(height: 12),
          StudentButton(
            label: 'Добавить пару',
            icon: 'plus',
            outlined: true,
            onPressed: () =>
                showStudyClassEditor(context, widget.store, date: _day),
          ),
        ],
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => showStudySubjects(context, widget.store),
          icon: const StudentIcon('book-open', size: 20),
          label: const Text('Мои предметы'),
        ),
      ],
    );
  }
}

Future<void> showStudyClass(
  BuildContext context,
  StudentStore store,
  String id,
) => Navigator.of(context).push(
  StudentRoute<void>(
    builder: (context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final c = store.classById(id);
        if (c == null) {
          return const StudentPage(
            title: 'Пара',
            child: Center(child: Text('Занятие удалено')),
          );
        }
        final subject = store.subjectById(c.subjectId),
            tasks = store.assignments.where((a) => a.classId == id).toList();
        return StudentPage(
          title: 'Пара',
          location: 'Пары / ${subject?.name ?? "Предмет"}',
          actions: [
            IconButton(
              tooltip: 'Изменить пару',
              onPressed: () =>
                  showStudyClassEditor(context, store, existing: c),
              icon: const StudentIcon('pencil-simple'),
            ),
          ],
          bottom: StudentButton(
            label: 'Открыть предмет',
            icon: 'book-open',
            onPressed: subject == null
                ? null
                : () => showStudySubject(context, store, subject.id),
          ),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: StudentBadge(c.title),
              ),
              const SizedBox(height: 18),
              Text(
                subject?.name ?? 'Предмет',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 16),
              Text(
                '${studyTime(c.startsAt)} — ${studyTime(c.endsAt)}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                studyDate(c.startsAt),
                style: const TextStyle(color: StudentColors.muted),
              ),
              const SizedBox(height: 24),
              _meta(
                'map-pin',
                'Аудитория',
                c.room.isEmpty ? 'Не указана' : c.room,
              ),
              _meta(
                'user-circle',
                'Преподаватель',
                c.teacher.isEmpty
                    ? (subject?.teacher.isEmpty ?? true
                          ? 'Не указан'
                          : subject!.teacher)
                    : c.teacher,
              ),
              const Divider(height: 36),
              Text(
                'К этой паре',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (tasks.isEmpty)
                const Text(
                  'Заданий к этой паре пока нет',
                  style: TextStyle(color: StudentColors.muted),
                )
              else
                ...tasks.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StudyAssignmentTile(store: store, assignment: a),
                  ),
                ),
              const SizedBox(height: 16),
              StudentButton(
                label: 'Добавить задание к паре',
                icon: 'plus',
                outlined: true,
                onPressed: () => showCreateStudyAssignment(
                  context,
                  store,
                  subjectId: c.subjectId,
                  classId: c.id,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _deleteClass(context, store, c),
                child: const Text(
                  'Удалить пару',
                  style: TextStyle(color: StudentColors.danger),
                ),
              ),
            ],
          ),
        );
      },
    ),
  ),
);

Widget _meta(String icon, String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 10),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      StudentIcon(icon, size: 20, color: StudentColors.muted),
      const SizedBox(width: 12),
      SizedBox(
        width: 100,
        child: Text(label, style: const TextStyle(color: StudentColors.muted)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ),
    ],
  ),
);

Future<void> showStudySubject(
  BuildContext context,
  StudentStore store,
  String id,
) => Navigator.of(context).push(
  StudentRoute<void>(
    builder: (context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = store.subjectById(id);
        if (s == null) {
          return const StudentPage(
            title: 'Предмет',
            child: Center(child: Text('Предмет удалён')),
          );
        }
        final tasks = store.assignmentsForSubject(id),
            classes =
                store.classes
                    .where(
                      (c) =>
                          c.subjectId == id && c.endsAt.isAfter(DateTime.now()),
                    )
                    .toList()
                  ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        return StudentPage(
          title: 'Предмет',
          location: 'Пары / Мои предметы',
          actions: [
            IconButton(
              tooltip: 'Изменить предмет',
              onPressed: () =>
                  showStudySubjectEditor(context, store, existing: s),
              icon: const StudentIcon('pencil-simple'),
            ),
          ],
          bottom: StudentButton(
            label: 'Задания по предмету',
            icon: 'list-bullets',
            onPressed: () => Navigator.of(context).push(
              StudentRoute<void>(
                builder: (context) => AnimatedBuilder(
                  animation: store,
                  builder: (context, _) => StudentPage(
                    title: s.name,
                    child: StudentAssignmentsScreen(
                      store: store,
                      initialSubjectId: id,
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(s.name, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 16),
              Text(
                s.teacher.isEmpty ? 'Преподаватель не указан' : s.teacher,
                style: const TextStyle(
                  color: StudentColors.muted,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: StudentColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Text(
                      '${tasks.where((a) => a.status != StudyStatus.done).length}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        color: StudentColors.accent,
                      ),
                    ),
                    const SizedBox(width: 24),
                    const Expanded(
                      child: Text(
                        'активных заданий\nпо предмету',
                        style: TextStyle(color: StudentColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Следующая пара',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (classes.isEmpty)
                const Text(
                  'Расписание пока не добавлено',
                  style: TextStyle(color: StudentColors.muted),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${studyDate(classes.first.startsAt)} · ${studyTime(classes.first.startsAt)}',
                  ),
                  subtitle: Text(classes.first.room),
                  trailing: const StudentIcon('caret-right'),
                  onTap: () => showStudyClass(context, store, classes.first.id),
                ),
              const SizedBox(height: 12),
              StudentButton(
                label: 'Добавить пару',
                outlined: true,
                icon: 'plus',
                onPressed: () =>
                    showStudyClassEditor(context, store, subjectId: id),
              ),
              const SizedBox(height: 24),
              Text(
                'Материалы из заданий',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              if (tasks.every((a) => a.materials.isEmpty))
                const Text(
                  'Добавляйте ссылки и файлы в контекст задания — они будут доступны здесь.',
                  style: TextStyle(color: StudentColors.muted, height: 1.5),
                )
              else
                ...tasks
                    .where((a) => a.materials.isNotEmpty)
                    .map(
                      (a) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const StudentIcon('paperclip'),
                        title: Text(a.title),
                        subtitle: Text('${a.materials.length} материалов'),
                        onTap: () => showStudyAssignment(context, store, a.id),
                      ),
                    ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () => _deleteSubject(context, store, s),
                child: const Text(
                  'Удалить предмет',
                  style: TextStyle(color: StudentColors.danger),
                ),
              ),
            ],
          ),
        );
      },
    ),
  ),
);

Future<void> showStudySubjects(BuildContext context, StudentStore store) =>
    Navigator.of(context).push(
      StudentRoute<void>(
        builder: (context) => AnimatedBuilder(
          animation: store,
          builder: (context, _) => StudentPage(
            title: 'Мои предметы',
            actions: [
              IconButton(
                tooltip: 'Добавить предмет',
                onPressed: () => showStudySubjectEditor(context, store),
                icon: const StudentIcon('plus'),
              ),
            ],
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (store.subjects.isEmpty)
                  const StudentEmpty(
                    title: 'Добавьте первый предмет',
                    message: 'Укажите название и преподавателя, затем добавьте пары и задания.',
                  ),
                ...store.subjects.map(
                  (s) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    leading: const StudentIcon('book-open'),
                    title: Text(
                      s.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      s.teacher.isEmpty ? 'Преподаватель не указан' : s.teacher,
                    ),
                    trailing: const StudentIcon('caret-right'),
                    onTap: () => showStudySubject(context, store, s.id),
                  ),
                ),
                const SizedBox(height: 24),
                StudentButton(
                  label: 'Добавить предмет',
                  icon: 'plus',
                  onPressed: () => showStudySubjectEditor(context, store),
                ),
              ],
            ),
          ),
        ),
      ),
    );

Future<void> showStudySubjectEditor(
  BuildContext context,
  StudentStore store, {
  StudySubject? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? ''),
      teacher = TextEditingController(text: existing?.teacher ?? '');
  final form = GlobalKey<FormState>();
  bool saving = false;
  String? error;
  final editorRoute = DialogRoute<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? 'Новый предмет' : 'Изменить предмет'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Название предмета',
                  ),
                  autofocus: true,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Введите название' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: teacher,
                  decoration: const InputDecoration(
                    labelText: 'Преподаватель · необязательно',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: StudentColors.danger),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => saving = true);
                    try {
                      if (existing == null) {
                        await store.createSubject(
                          name: name.text.trim(),
                          teacher: teacher.text.trim(),
                        );
                      } else {
                        await store.updateSubject(
                          existing.copyWith(
                            name: name.text.trim(),
                            teacher: teacher.text.trim(),
                          ),
                        );
                      }
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      setState(() {
                        saving = false;
                        error = e.toString().replaceFirst('Exception: ', '');
                      });
                    }
                  },
            child: Text(saving ? 'Сохраняем…' : 'Сохранить'),
          ),
        ],
      ),
    ),
  );
  await Navigator.of(context).push(editorRoute);
  await editorRoute.completed;
  name.dispose();
  teacher.dispose();
}

Future<void> showStudyClassEditor(
  BuildContext context,
  StudentStore store, {
  StudyClass? existing,
  DateTime? date,
  String? subjectId,
}) async {
  if (store.subjects.isEmpty) {
    await showStudySubjectEditor(context, store);
    if (!context.mounted || store.subjects.isEmpty) return;
  }
  final form = GlobalKey<FormState>(),
      title = TextEditingController(
        text: existing?.title ?? 'Практическое занятие',
      ),
      room = TextEditingController(text: existing?.room ?? ''),
      teacher = TextEditingController(text: existing?.teacher ?? '');
  String selected = existing?.subjectId ?? subjectId ?? store.subjects.first.id;
  DateTime day = DateUtils.dateOnly(
    existing?.startsAt ?? date ?? DateTime.now(),
  );
  TimeOfDay start = TimeOfDay.fromDateTime(
        existing?.startsAt ?? DateTime(day.year, day.month, day.day, 9),
      ),
      end = TimeOfDay.fromDateTime(
        existing?.endsAt ?? DateTime(day.year, day.month, day.day, 10, 30),
      );
  bool saving = false;
  String? error;
  final editorRoute = DialogRoute<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? 'Новая пара' : 'Изменить пару'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: 'Предмет'),
                    items: store.subjects
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) selected = v;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Тип занятия'),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Укажите тип занятия'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Дата'),
                    subtitle: Text(studyDate(day)),
                    trailing: const StudentIcon('calendar-blank'),
                    onTap: () async {
                      final chosen = await showDatePicker(
                        context: context,
                        initialDate: day,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (chosen != null) setState(() => day = chosen);
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: start,
                            );
                            if (t != null) setState(() => start = t);
                          },
                          child: Text('Начало ${start.format(context)}'),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: end,
                            );
                            if (t != null) setState(() => end = t);
                          },
                          child: Text('Конец ${end.format(context)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: room,
                    decoration: const InputDecoration(
                      labelText: 'Аудитория / ссылка на занятие',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: teacher,
                    decoration: const InputDecoration(
                      labelText: 'Преподаватель · необязательно',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: StudentColors.danger),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    final begins = DateTime(
                          day.year,
                          day.month,
                          day.day,
                          start.hour,
                          start.minute,
                        ),
                        ends = DateTime(
                          day.year,
                          day.month,
                          day.day,
                          end.hour,
                          end.minute,
                        );
                    if (!ends.isAfter(begins)) {
                      setState(
                        () => error = 'Конец пары должен быть позже начала',
                      );
                      return;
                    }
                    setState(() => saving = true);
                    try {
                      if (existing == null) {
                        await store.createClass(
                          subjectId: selected,
                          title: title.text.trim(),
                          startsAt: begins,
                          endsAt: ends,
                          room: room.text.trim(),
                          teacher: teacher.text.trim(),
                        );
                      } else {
                        await store.updateClass(
                          existing.copyWith(
                            subjectId: selected,
                            title: title.text.trim(),
                            startsAt: begins,
                            endsAt: ends,
                            room: room.text.trim(),
                            teacher: teacher.text.trim(),
                          ),
                        );
                      }
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      setState(() {
                        saving = false;
                        error = e.toString().replaceFirst('Exception: ', '');
                      });
                    }
                  },
            child: Text(saving ? 'Сохраняем…' : 'Сохранить'),
          ),
        ],
      ),
    ),
  );
  await Navigator.of(context).push(editorRoute);
  await editorRoute.completed;
  title.dispose();
  room.dispose();
  teacher.dispose();
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
    ) ??
    false;
Future<void> _deleteClass(
  BuildContext context,
  StudentStore store,
  StudyClass c,
) async {
  if (!await _confirm(
    context,
    'Удалить пару?',
    'Задания сохранятся без привязки к этому занятию.',
  )) {
    return;
  }
  if (!context.mounted) return;
  await studentGuard(context, () async {
    await store.deleteClass(c.id);
    if (context.mounted) Navigator.pop(context);
  });
}

Future<void> _deleteSubject(
  BuildContext context,
  StudentStore store,
  StudySubject s,
) async {
  if (!await _confirm(
    context,
    'Удалить предмет?',
    'Удалить можно только предмет без пар и заданий.',
  )) {
    return;
  }
  if (!context.mounted) return;
  await studentGuard(context, () async {
    await store.deleteSubject(s.id);
    if (context.mounted) Navigator.pop(context);
  });
}

class StudentProfileScreen extends StatelessWidget {
  const StudentProfileScreen({
    super.key,
    required this.store,
    required this.onSchedule,
  });
  final StudentStore store;
  final VoidCallback onSchedule;
  @override
  Widget build(BuildContext context) {
    final p = store.profile,
        initials = p.name
            .trim()
            .split(RegExp(r'\s+'))
            .where((v) => v.isNotEmpty)
            .take(2)
            .map((v) => v.characters.first)
            .join();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: StudentColors.cream,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                initials.isEmpty ? 'Я' : initials,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: StudentColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    '${p.group.isEmpty ? 'Группа не указана' : p.group} · ${p.course} курс',
                    style: const TextStyle(color: StudentColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: StudentBadge(
            store.isDemo ? 'Демонстрационный профиль' : 'Учебный профиль',
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        _meta(
          'graduation-cap',
          'Группа',
          p.group.isEmpty ? 'Не указана' : p.group,
        ),
        _meta('graduation-cap', 'Курс', '${p.course}'),
        _meta('user-circle', 'Подгруппа', '${p.subgroup}'),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const StudentIcon('pencil-simple'),
          title: const Text('Изменить профиль'),
          trailing: const StudentIcon('caret-right'),
          onTap: () => _editProfile(context, store),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const StudentIcon('bell-simple'),
          title: const Text('Уведомления'),
          trailing: const StudentIcon('caret-right'),
          onTap: () => showStudentNotifications(context, store),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const StudentIcon('calendar-blank'),
          title: const Text('Моё расписание'),
          trailing: const StudentIcon('caret-right'),
          onTap: onSchedule,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const StudentIcon('book-open'),
          title: const Text('Мои предметы'),
          trailing: const StudentIcon('caret-right'),
          onTap: () => showStudySubjects(context, store),
        ),
        const SizedBox(height: 24),
        const Text(
          'Напоминания отображаются внутри приложения по выбранному сроку. Внешние push-уведомления не подключены.',
          style: TextStyle(
            fontSize: 12,
            color: StudentColors.muted,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),
        if (store.isDemo)
          StudentButton(
            label: 'Сбросить демонстрационные данные',
            outlined: true,
            onPressed: () => studentGuard(context, () async {
              await store.resetDemo();
            }),
          ),
        const SizedBox(height: 12),
        StudentButton(
          label: 'Выйти',
          outlined: true,
          onPressed: () => studentGuard(context, () async {
            await store.logout();
          }),
        ),
      ],
    );
  }
}

Future<void> _editProfile(BuildContext context, StudentStore store) async {
  final p = store.profile,
      name = TextEditingController(text: store.profile.name),
      group = TextEditingController(text: store.profile.group),
      course = TextEditingController(text: '${store.profile.course}'),
      subgroup = TextEditingController(text: '${store.profile.subgroup}');
  final form = GlobalKey<FormState>();
  bool saving = false;
  String? error;
  final editorRoute = DialogRoute<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Профиль студента'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StudentFieldLabel('Имя'),
                  TextFormField(
                    key: const ValueKey('profile-name'),
                    controller: name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'Имя и фамилия',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Введите имя' : null,
                  ),
                  const SizedBox(height: 16),
                  const StudentFieldLabel('Учебная группа'),
                  TextFormField(
                    key: const ValueKey('profile-group'),
                    controller: group,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'Например, ИС-21',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const StudentFieldLabel('Курс'),
                  TextFormField(
                    key: const ValueKey('profile-course'),
                    controller: course,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: '1–8',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1 || n > 8
                          ? 'Курс от 1 до 8'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const StudentFieldLabel('Подгруппа'),
                  TextFormField(
                    key: const ValueKey('profile-subgroup'),
                    controller: subgroup,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: '1–20',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1 || n > 20
                          ? 'Подгруппа от 1 до 20'
                          : null;
                    },
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: StudentColors.danger),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    FocusScope.of(context).unfocus();
                    if (!form.currentState!.validate()) return;
                    setState(() => saving = true);
                    try {
                      await store.updateProfile(
                        p.copyWith(
                          name: name.text.trim(),
                          group: group.text.trim(),
                          course: int.parse(course.text),
                          subgroup: int.parse(subgroup.text),
                        ),
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      setState(() {
                        saving = false;
                        error = e.toString();
                      });
                    }
                  },
            child: Text(saving ? 'Сохраняем…' : 'Сохранить'),
          ),
        ],
      ),
    ),
  );
  await Navigator.of(context).push(editorRoute);
  await editorRoute.completed;
  name.dispose();
  group.dispose();
  course.dispose();
  subgroup.dispose();
}

Future<void> showStudentNotifications(
  BuildContext context,
  StudentStore store,
) => Navigator.of(context).push(
  StudentRoute<void>(
    builder: (context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final now = DateTime.now(),
            tasks =
                store.assignments
                    .where(
                      (a) =>
                          a.status != StudyStatus.done &&
                          a.reminderMinutes != null &&
                          !a.dueAt
                              .subtract(Duration(minutes: a.reminderMinutes!))
                              .isAfter(now),
                    )
                    .toList()
                  ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
        final classes = store.classes
            .where(
              (c) =>
                  c.startsAt.isAfter(now) &&
                  c.startsAt.difference(now).inMinutes <= 30,
            )
            .toList();
        return StudentPage(
          title: 'Уведомления',
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Напоминания',
                style: TextStyle(fontSize: 13, color: StudentColors.muted),
              ),
              const SizedBox(height: 16),
              if (tasks.isEmpty && classes.isEmpty)
                const StudentEmpty(
                  title: 'Всё спокойно',
                  message: 'Здесь появятся напоминания о заданиях и ближайших парах.',
                ),
              ...tasks.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: StudyAssignmentTile(
                    store: store,
                    assignment: a,
                    highlight: true,
                  ),
                ),
              ),
              ...classes.map(
                (c) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  leading: const StudentIcon('calendar-blank'),
                  title: Text(
                    'Скоро ${store.subjectById(c.subjectId)?.name ?? 'пара'}',
                  ),
                  subtitle: Text('${studyTime(c.startsAt)} · ${c.room}'),
                  trailing: const StudentIcon('caret-right'),
                  onTap: () => showStudyClass(context, store, c.id),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Напоминания вычисляются из ваших сроков и выбранного времени. Данные обновляются при открытии приложения.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: StudentColors.muted,
                ),
              ),
            ],
          ),
        );
      },
    ),
  ),
);
