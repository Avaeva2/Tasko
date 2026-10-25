import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'student_models.dart';
import 'student_store.dart';
import 'student_theme.dart';
import 'student_widgets.dart';

/// Shared entry points keep the same assignment live in Today, the board and
/// subject screens. Editors own a draft; the store changes only after Save.
Future<void> showStudyAssignment(
  BuildContext context,
  StudentStore store,
  String id,
) async {
  await Navigator.of(context).push<void>(
    StudentRoute(
      builder: (_) => StudyAssignmentScreen(store: store, assignmentId: id),
    ),
  );
}

Future<void> showCreateStudyAssignment(
  BuildContext context,
  StudentStore store, {
  String? subjectId,
  String? classId,
}) async {
  final id = await Navigator.of(context).push<String>(
    StudentRoute(
      builder: (_) => StudyAssignmentEditor(
        store: store,
        subjectId: subjectId,
        classId: classId,
      ),
    ),
  );
  if (context.mounted && id != null) {
    await showStudyAssignment(context, store, id);
  }
}

class StudyAssignmentScreen extends StatefulWidget {
  const StudyAssignmentScreen({
    super.key,
    required this.store,
    required this.assignmentId,
  });

  final StudentStore store;
  final String assignmentId;

  @override
  State<StudyAssignmentScreen> createState() => _StudyAssignmentScreenState();
}

class _StudyAssignmentScreenState extends State<StudyAssignmentScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit({bool contextOnly = false}) async {
    final assignment = widget.store.assignmentById(widget.assignmentId);
    if (assignment == null) return;
    await Navigator.of(context).push<String>(
      StudentRoute(
        builder: (_) => StudyAssignmentEditor(
          store: widget.store,
          assignment: assignment,
          contextOnly: contextOnly,
        ),
      ),
    );
  }

  Future<void> _addChecklistItem() async {
    final text = await _askText(
      context,
      title: 'Новый пункт плана',
      label: 'Что нужно сделать',
      action: 'Добавить',
    );
    if (text == null) return;
    await _mutate(
      () => widget.store.addChecklistItem(widget.assignmentId, text),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить задание?'),
        content: const Text('Задание и его материалы будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _mutate(() => widget.store.deleteAssignment(widget.assignmentId));
    if (mounted && _error == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final task = widget.store.assignmentById(widget.assignmentId);
      if (task == null) {
        return const Scaffold(
          body: SafeArea(child: Center(child: Text('Задание удалено'))),
        );
      }
      final subject = widget.store.subjectById(task.subjectId);
      final linkedClass = task.classId == null
          ? null
          : widget.store.classById(task.classId!);
      final done = task.status == StudyStatus.done;
      return _AssignmentScaffold(
        appBar: AppBar(
          title: StudentLocationTitle(
            'Задание',
            location: 'Задания / ${subject?.name ?? "Предмет"}',
          ),
          toolbarHeight: 70,
          actions: [
            IconButton(
              tooltip: 'Редактировать задание',
              onPressed: _busy ? null : () => _edit(),
              icon: const StudentIcon('note-pencil'),
            ),
            PopupMenuButton<String>(
              tooltip: 'Действия с заданием',
              icon: const StudentIcon('dots-three'),
              onSelected: (value) {
                if (value == 'delete') _delete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Удалить задание')),
              ],
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: StudentButton(
              label: done ? 'Вернуть в работу' : 'Завершить задание',
              icon: done ? 'arrow-counter-clockwise' : 'check',
              outlined: done,
              busy: _busy,
              onPressed: _busy
                  ? null
                  : () => _mutate(
                      () => widget.store.setStatus(
                        task.id,
                        done ? StudyStatus.inProgress : StudyStatus.done,
                      ),
                    ),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: StudentBadge(subject?.name ?? 'Предмет'),
            ),
            const SizedBox(height: 18),
            Text(
              task.title,
              style: const TextStyle(
                fontSize: 30,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: DropdownButton<StudyStatus>(
                key: const ValueKey('assignment-status'),
                value: task.status,
                underline: const SizedBox.shrink(),
                icon: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: StudentIcon('caret-down', size: 16),
                ),
                items: StudyStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: StudentBadge(status.label),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (status) {
                        if (status != null) {
                          _mutate(
                            () => widget.store.setStatus(task.id, status),
                          );
                        }
                      },
              ),
            ),
            const SizedBox(height: 12),
            _InfoSurface(
              children: [
                const Text(
                  'Срок сдачи',
                  style: TextStyle(fontSize: 12, color: StudentColors.muted),
                ),
                const SizedBox(height: 8),
                Text(
                  _dateTimeLabel(task.dueAt),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: task.isOverdue
                        ? StudentColors.danger
                        : StudentColors.ink,
                  ),
                ),
                if (task.reminderAt != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Напомнить ${_dateTimeLabel(task.reminderAt!)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: StudentColors.muted,
                    ),
                  ),
                ],
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _InlineError(_error!),
            ],
            const SizedBox(height: 26),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Контекст задания',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  key: const ValueKey('edit-assignment-context'),
                  onPressed: _busy ? null : () => _edit(contextOnly: true),
                  child: Text(
                    task.description.isEmpty && task.materials.isEmpty
                        ? 'Добавить'
                        : 'Изменить',
                  ),
                ),
              ],
            ),
            Text(
              task.description.isEmpty
                  ? 'Добавьте условие, заметки или материалы, чтобы всё было под рукой.'
                  : task.description,
              style: TextStyle(
                fontSize: 15,
                height: 1.55,
                color: task.description.isEmpty
                    ? StudentColors.muted
                    : StudentColors.ink,
              ),
            ),
            if (linkedClass != null) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StudentIcon(
                    'graduation-cap',
                    size: 20,
                    color: StudentColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${linkedClass.title}\n${_dateTimeLabel(linkedClass.startsAt)}${linkedClass.room.isEmpty ? '' : ' · ${linkedClass.room}'}',
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ),
                ],
              ),
            ],
            if (task.materials.isNotEmpty) ...[
              const SizedBox(height: 18),
              for (final material in task.materials)
                _MaterialRow(
                  material: material,
                  onOpen: () => _openMaterial(context, widget.store, material),
                ),
            ],
            const SizedBox(height: 28),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'План работы',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Добавить пункт плана',
                  onPressed: _busy ? null : _addChecklistItem,
                  icon: const StudentIcon('plus', size: 22),
                ),
              ],
            ),
            if (task.checklist.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Разбейте работу на небольшие шаги.',
                  style: TextStyle(color: StudentColors.muted),
                ),
              ),
            for (final item in task.checklist)
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      key: ValueKey('checklist-${item.id}'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 15,
                          color: item.done
                              ? StudentColors.muted
                              : StudentColors.ink,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      value: item.done,
                      onChanged: _busy
                          ? null
                          : (value) => _mutate(
                              () => widget.store.toggleChecklist(
                                task.id,
                                item.id,
                                value ?? false,
                              ),
                            ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Удалить пункт',
                    onPressed: _busy
                        ? null
                        : () => _mutate(
                            () => widget.store.deleteChecklistItem(
                              task.id,
                              item.id,
                            ),
                          ),
                    icon: const StudentIcon(
                      'trash',
                      size: 18,
                      color: StudentColors.muted,
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    },
  );
}

class StudyAssignmentEditor extends StatefulWidget {
  const StudyAssignmentEditor({
    super.key,
    required this.store,
    this.assignment,
    this.subjectId,
    this.classId,
    this.contextOnly = false,
  });

  final StudentStore store;
  final StudyAssignment? assignment;
  final String? subjectId, classId;
  final bool contextOnly;

  @override
  State<StudyAssignmentEditor> createState() => _StudyAssignmentEditorState();
}

class _StudyAssignmentEditorState extends State<StudyAssignmentEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _description;
  late String? _subjectId, _classId;
  late DateTime _dueAt;
  late int? _reminderMinutes;
  late List<StudyMaterial> _materials;
  bool _dirty = false, _saving = false, _pickingFile = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final original = widget.assignment;
    _title = TextEditingController(text: original?.title ?? '');
    _description = TextEditingController(text: original?.description ?? '');
    _subjectId =
        original?.subjectId ??
        widget.subjectId ??
        widget.store.subjects.firstOrNull?.id;
    _classId = original?.classId ?? widget.classId;
    if (_classId != null &&
        widget.store.classById(_classId!)?.subjectId != _subjectId) {
      _classId = null;
    }
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _dueAt =
        original?.dueAt.toLocal() ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18);
    _reminderMinutes = original == null ? 1440 : original.reminderMinutes;
    _materials = List.of(original?.materials ?? const <StudyMaterial>[]);
    _title.addListener(_changed);
    _description.addListener(_changed);
  }

  void _changed() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    if (_saving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Не сохранять изменения?'),
          content: const Text('Исходное задание останется без изменений.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Продолжить'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Не сохранять'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Срок сдачи',
    );
    if (date == null || !mounted) return;
    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        _dueAt.hour,
        _dueAt.minute,
      );
      _dirty = true;
    });
  }

  Future<void> _chooseTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt),
      helpText: 'Время сдачи',
    );
    if (time == null || !mounted) return;
    setState(() {
      _dueAt = DateTime(
        _dueAt.year,
        _dueAt.month,
        _dueAt.day,
        time.hour,
        time.minute,
      );
      _dirty = true;
    });
  }

  Future<void> _addLink({StudyMaterial? current}) async {
    final result = await Navigator.of(context).push<StudyMaterial>(
      StudentRoute(builder: (_) => StudyLinkEditor(material: current)),
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = _materials.indexWhere(
        (material) => material.id == result.id,
      );
      if (index < 0) {
        _materials.add(result);
      } else {
        _materials[index] = result;
      }
      _dirty = true;
    });
  }

  Future<void> _addFile() async {
    if (_pickingFile || _saving) return;
    setState(() {
      _pickingFile = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Материал к заданию',
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('Не удалось прочитать файл. Выберите его ещё раз.');
      }
      if (bytes.length > 2 * 1024 * 1024) {
        throw StateError('Выберите файл размером до 2 МБ.');
      }
      setState(() {
        _materials.add(
          StudyMaterial(
            id: const Uuid().v4(),
            name: file.name,
            bytes: Uint8List.fromList(bytes),
            mimeType: _mimeType(file.extension),
          ),
        );
        _dirty = true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _pickingFile || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final subjectId = _subjectId;
    if (subjectId == null) {
      setState(() => _error = 'Сначала добавьте предмет.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final original = widget.assignment;
      String savedId;
      if (original == null) {
        final created = await widget.store.createAssignment(
          title: _title.text.trim(),
          subjectId: subjectId,
          dueAt: _dueAt,
          description: _description.text.trim(),
          classId: _classId,
          reminderMinutes: _reminderMinutes,
          materials: _materials,
        );
        savedId = created.id;
      } else if (widget.contextOnly) {
        await widget.store.updateContext(
          original.id,
          description: _description.text.trim(),
          subjectId: subjectId,
          classId: _classId,
          materials: _materials,
        );
        savedId = original.id;
      } else {
        // Read the latest value so an independently saved checklist/status is
        // never overwritten by the editor's older snapshot.
        final latest = widget.store.assignmentById(original.id);
        if (latest == null) throw StateError('Задание уже удалено.');
        await widget.store.updateAssignment(
          latest.copyWith(
            title: _title.text.trim(),
            subjectId: subjectId,
            description: _description.text.trim(),
            dueAt: _dueAt,
            classId: _classId,
            reminderMinutes: _reminderMinutes,
            materials: _materials,
          ),
        );
        savedId = original.id;
      }
      if (mounted) {
        _dirty = false;
        Navigator.pop(context, savedId);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _errorMessage(error));
        showStudentMessage(context, _errorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes =
        widget.store.classes
            .where((item) => item.subjectId == _subjectId)
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return PopScope<String>(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: _AssignmentScaffold(
        appBar: AppBar(
          title: Text(
            widget.contextOnly
                ? 'Контекст задания'
                : widget.assignment == null
                ? 'Новое задание'
                : 'Изменить задание',
          ),
          leading: IconButton(
            tooltip: 'Отмена',
            onPressed: _saving ? null : _cancel,
            icon: const StudentIcon('arrow-left'),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _cancel,
              child: const Text('Отмена'),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: StudentButton(
              label: widget.contextOnly
                  ? 'Сохранить контекст'
                  : widget.assignment == null
                  ? 'Добавить задание'
                  : 'Сохранить изменения',
              busy: _saving,
              onPressed: _saving || _pickingFile ? null : _save,
            ),
          ),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              if (!widget.contextOnly) ...[
                const StudentFieldLabel('Название'),
                TextFormField(
                  key: const ValueKey('assignment-title-input'),
                  controller: _title,
                  enabled: !_saving,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    hintText: 'Например, лабораторная работа №3',
                    counterText: '',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Введите название задания'
                      : null,
                ),
                const SizedBox(height: 20),
              ],
              const StudentFieldLabel('Предмет'),
              DropdownButtonFormField<String>(
                key: ValueKey('subject-$_subjectId'),
                initialValue: _subjectId,
                isExpanded: true,
                decoration: const InputDecoration(hintText: 'Выберите предмет'),
                items: widget.store.subjects
                    .map(
                      (subject) => DropdownMenuItem(
                        value: subject.id,
                        child: Text(
                          subject.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _subjectId = value;
                        if (_classId != null &&
                            widget.store.classById(_classId!)?.subjectId !=
                                value) {
                          _classId = null;
                        }
                        _dirty = true;
                      }),
                validator: (value) => value == null ? 'Выберите предмет' : null,
              ),
              const SizedBox(height: 20),
              const StudentFieldLabel('Связанная пара · необязательно'),
              DropdownButtonFormField<String>(
                key: ValueKey('linked-class-$_subjectId-$_classId'),
                initialValue: _classId ?? '',
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Без привязки к паре'),
                  ),
                  for (final item in classes)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        '${_shortDate(item.startsAt)} · ${item.title}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _classId = value == '' ? null : value;
                        _dirty = true;
                      }),
              ),
              if (classes.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'У этого предмета пока нет пар.',
                    style: TextStyle(fontSize: 12, color: StudentColors.muted),
                  ),
                ),
              if (!widget.contextOnly) ...[
                const SizedBox(height: 22),
                const StudentFieldLabel('Срок сдачи'),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _PickerTile(
                        label: _shortDate(_dueAt),
                        icon: 'calendar-blank',
                        onTap: _saving ? null : _chooseDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _PickerTile(
                        label: _timeLabel(_dueAt),
                        icon: 'clock',
                        onTap: _saving ? null : _chooseTime,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const StudentFieldLabel('Напоминание'),
                DropdownButtonFormField<int>(
                  initialValue: _reminderMinutes ?? -1,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: -1, child: Text('Не напоминать')),
                    DropdownMenuItem(value: 0, child: Text('В срок сдачи')),
                    DropdownMenuItem(value: 60, child: Text('За час до срока')),
                    DropdownMenuItem(
                      value: 1440,
                      child: Text('За день до срока'),
                    ),
                    DropdownMenuItem(
                      value: 2880,
                      child: Text('За два дня до срока'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _reminderMinutes = value == -1 ? null : value;
                          _dirty = true;
                        }),
                ),
                if (_reminderMinutes != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Напоминание: ${_dateTimeLabel(_dueAt.subtract(Duration(minutes: _reminderMinutes!)))}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: StudentColors.muted,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 22),
              TextFormField(
                key: const ValueKey('assignment-description-input'),
                controller: _description,
                enabled: !_saving,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Описание и условие',
                  alignLabelWithHint: true,
                  hintText:
                      'Запишите условие, требования к работе или свои заметки',
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Материалы',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (_materials.isEmpty)
                const Text(
                  'Добавьте ссылку на условие или файл до 2 МБ.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: StudentColors.muted,
                  ),
                ),
              for (final material in _materials)
                _MaterialRow(
                  material: material,
                  onOpen: () => material.isLink
                      ? _addLink(current: material)
                      : _openMaterial(context, widget.store, material),
                  onRemove: _saving
                      ? null
                      : () => setState(() {
                          _materials.removeWhere(
                            (item) => item.id == material.id,
                          );
                          _dirty = true;
                        }),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    key: const ValueKey('add-assignment-link'),
                    onPressed: _saving ? null : () => _addLink(),
                    icon: const StudentIcon('arrow-right', size: 18),
                    label: const Text('Добавить ссылку'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('add-assignment-file'),
                    onPressed: _saving || _pickingFile ? null : _addFile,
                    icon: const StudentIcon('paperclip', size: 18),
                    label: Text(
                      _pickingFile ? 'Читаем файл…' : 'Добавить файл',
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _InlineError(_error!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class StudyLinkEditor extends StatefulWidget {
  const StudyLinkEditor({super.key, this.material});
  final StudyMaterial? material;

  @override
  State<StudyLinkEditor> createState() => _StudyLinkEditorState();
}

class _StudyLinkEditorState extends State<StudyLinkEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _url;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.material?.name ?? '');
    _url = TextEditingController(text: widget.material?.url ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      StudyMaterial(
        id: widget.material?.id ?? const Uuid().v4(),
        name: _name.text.trim(),
        url: _url.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _AssignmentScaffold(
    appBar: AppBar(
      title: Text(
        widget.material == null ? 'Добавить ссылку' : 'Изменить ссылку',
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: StudentButton(
          label: widget.material == null
              ? 'Добавить ссылку'
              : 'Сохранить ссылку',
          onPressed: _save,
        ),
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Материал к заданию',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          const StudentFieldLabel('Название материала'),
          TextFormField(
            key: const ValueKey('material-name-input'),
            controller: _name,
            maxLength: 160,
            decoration: const InputDecoration(
              hintText: 'Например, условие лабораторной',
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Введите название материала'
                : null,
          ),
          const SizedBox(height: 20),
          const StudentFieldLabel('Ссылка'),
          TextFormField(
            key: const ValueKey('material-url-input'),
            controller: _url,
            maxLength: 2048,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'https://…'),
            validator: validateStudyMaterialUrl,
          ),
          const SizedBox(height: 12),
          const Text(
            'Ссылку можно будет открыть из задания. Материал сохранится вместе с контекстом.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: StudentColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

String? validateStudyMaterialUrl(String? value) {
  final url = value?.trim() ?? '';
  final uri = Uri.tryParse(url);
  if (url.isEmpty) return 'Введите ссылку';
  if (url.length > 2048 ||
      uri == null ||
      !['https', 'http'].contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      url.contains(RegExp(r'\s'))) {
    return 'Укажите корректную ссылку с http:// или https://';
  }
  return null;
}

class _AssignmentScaffold extends StatelessWidget {
  const _AssignmentScaffold({
    required this.appBar,
    required this.body,
    this.bottomNavigationBar,
  });
  final PreferredSizeWidget appBar;
  final Widget body;
  final Widget? bottomNavigationBar;

  Widget _constrain(Widget child) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appBar,
    body: _constrain(body),
    bottomNavigationBar: bottomNavigationBar == null
        ? null
        : _constrain(bottomNavigationBar!),
  );
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.material,
    required this.onOpen,
    this.onRemove,
  });
  final StudyMaterial material;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: StudentIcon(
      material.isLink ? 'arrow-right' : 'paperclip',
      size: 22,
      color: StudentColors.accent,
    ),
    title: Text(
      material.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    subtitle: Text(
      material.isLink
          ? Uri.tryParse(material.url ?? '')?.host ?? ''
          : '${_sizeLabel(material.size)} · файл',
      style: const TextStyle(fontSize: 12, color: StudentColors.muted),
    ),
    onTap: onOpen,
    trailing: onRemove == null
        ? const StudentIcon('caret-right', size: 18, color: StudentColors.muted)
        : IconButton(
            tooltip: 'Удалить материал',
            onPressed: onRemove,
            icon: const StudentIcon(
              'trash',
              size: 18,
              color: StudentColors.muted,
            ),
          ),
  );
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label, icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: StudentColors.surface,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            StudentIcon(icon, size: 20, color: StudentColors.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          ],
        ),
      ),
    ),
  );
}

class _InfoSurface extends StatelessWidget {
  const _InfoSurface({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: StudentColors.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: const TextStyle(
        color: StudentColors.danger,
        fontSize: 14,
        height: 1.5,
      ),
    ),
  );
}

Future<void> _openMaterial(
  BuildContext context,
  StudentStore store,
  StudyMaterial material,
) async {
  try {
    final url = material.url;
    if (url != null) {
      if (validateStudyMaterialUrl(url) != null) {
        throw StateError('У материала некорректная ссылка.');
      }
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Не удалось открыть ссылку.');
      return;
    }
    final download = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(material.name),
        content: Text(
          '${_sizeLabel(material.size)}\n${material.mimeType ?? 'Файл'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Закрыть'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Скачать файл'),
          ),
        ],
      ),
    );
    if (download != true) return;
    final bytes = material.bytes ?? await store.readMaterial(material);
    await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить материал',
      fileName: material.name,
      bytes: bytes,
    );
  } catch (error) {
    if (context.mounted) {
      showStudentMessage(context, _errorMessage(error));
    }
  }
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _ChecklistItemDialog(title: title, label: label, action: action),
);

class _ChecklistItemDialog extends StatefulWidget {
  const _ChecklistItemDialog({
    required this.title,
    required this.label,
    required this.action,
  });
  final String title, label, action;
  @override
  State<_ChecklistItemDialog> createState() => _ChecklistItemDialogState();
}

class _ChecklistItemDialogState extends State<_ChecklistItemDialog> {
  final _controller = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        maxLength: 160,
        decoration: InputDecoration(labelText: widget.label),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Введите текст' : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      TextButton(
        onPressed: () {
          if (_form.currentState?.validate() ?? false) {
            Navigator.pop(context, _controller.text.trim());
          }
        },
        child: Text(widget.action),
      ),
    ],
  );
}

const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];
String _timeLabel(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String _shortDate(DateTime date) => '${date.day} ${_months[date.month - 1]}';
String _dateTimeLabel(DateTime date) =>
    '${_shortDate(date.toLocal())}, ${_timeLabel(date.toLocal())}';
String _sizeLabel(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ'
    : bytes >= 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} КБ'
    : '$bytes Б';
String _errorMessage(Object error) => error.toString().replaceFirst(
  RegExp(
    r'^(Bad state|Exception|StateError|ArgumentError|Invalid argument\(s\)):\s*',
  ),
  '',
);
String _mimeType(String? extension) => switch (extension?.toLowerCase()) {
  'pdf' => 'application/pdf',
  'txt' || 'md' => 'text/plain',
  'csv' => 'text/csv',
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'webp' => 'image/webp',
  'zip' => 'application/zip',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'pptx' =>
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  _ => 'application/octet-stream',
};
