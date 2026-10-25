import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'student_assignment_screens.dart';
import 'student_board_order.dart';
import 'student_formatters.dart';
import 'student_models.dart';
import 'student_store.dart';
import 'student_theme.dart';
import 'student_widgets.dart';

/// Horizontal board with an explicit origin, insertion slot and acknowledged
/// save. The source stays mounted until the native draggable has ended.
class StudentKanban extends StatefulWidget {
  const StudentKanban({
    super.key,
    required this.store,
    required this.assignments,
    this.onInteractionChanged,
  });
  final StudentStore store;
  final List<StudyAssignment> assignments;
  final ValueChanged<bool>? onInteractionChanged;
  @override
  State<StudentKanban> createState() => _StudentKanbanState();
}

class _StudentKanbanState extends State<StudentKanban>
    with TickerProviderStateMixin {
  static const _width = 272.0, _inset = 8.0;
  final _dragFocus = FocusNode(debugLabel: 'Kanban drag');
  final _horizontal = ScrollController();
  final _vertical = List.generate(3, (_) => ScrollController());
  final _bodies = List.generate(3, (_) => GlobalKey());
  final _viewport = GlobalKey(), _slot = GlobalKey();
  final _cards = <String, GlobalKey>{};
  final _message = ValueNotifier<String>('');
  late final Ticker _edgeTicker = createTicker(_edgeScroll);
  final _flights = <OverlayEntry>{};
  final _controllers = <AnimationController>{};
  StudyAssignment? _moving;
  StudyStatus? _target;
  int _index = 0, _originIndex = 0, _visible = 0;
  String? _oldPrevious, _oldNext;
  String _phase = '', _notice = '';
  String? _error;
  Offset? _pointer;
  Rect? _originRect;
  bool _cancel = false;
  int _generation = 0;
  Duration? _lastTick;
  Future<void> Function()? _retry;

  double get _height {
    final scale = MediaQuery.textScalerOf(context);
    return 28 +
        (scale.scale(12) * 1.4).ceilToDouble() +
        8 +
        (scale.scale(16) * 1.35 * 3).ceilToDouble() +
        10 +
        math.max(48, scale.scale(12) * 1.4 * 2);
  }

  double get _extent => _height + 10;
  List<StudyAssignment> _column(StudyStatus status) =>
      widget.assignments
          .where((a) => a.status == status && a.id != _moving?.id)
          .toList()
        ..sort(compareStudyBoard);
  Rect? _rect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize && box.attached
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  @override
  void dispose() {
    _generation++;
    _edgeTicker.dispose();
    for (final entry in _flights) {
      entry.remove();
      entry.dispose();
    }
    for (final controller in _controllers) {
      controller.dispose();
    }
    _dragFocus.dispose();
    _message.dispose();
    _horizontal.dispose();
    for (final scroll in _vertical) {
      scroll.dispose();
    }
    super.dispose();
  }

  void _showColumn(int index) {
    if (!_horizontal.hasClients) return;
    _horizontal.animateTo(
      _horizontal.position.maxScrollExtent * index / 2,
      duration: StudentMotion.duration(context, StudentMotion.normal),
      curve: StudentMotion.curve,
    );
  }

  void _start(StudyAssignment assignment) {
    if (_moving != null) return;
    final items = _column(assignment.status);
    final index = items.indexWhere((a) => a.id == assignment.id);
    _originRect = _rect(_cards[assignment.id]!);
    _oldPrevious = index > 0 ? items[index - 1].id : null;
    _oldNext = index + 1 < items.length ? items[index + 1].id : null;
    _cancel = false;
    _pointer = null;
    _lastTick = null;
    setState(() {
      _moving = assignment;
      _originIndex = index;
      _target = assignment.status;
      _index = index;
      _phase = 'dragging';
      _error = null;
      _retry = null;
    });
    _message.value = '${assignment.status.label} · выберите место';
    widget.onInteractionChanged?.call(true);
    _dragFocus.requestFocus();
    HapticFeedback.selectionClick();
  }

  void _update(Offset pointer) {
    _pointer = pointer;
    if (_phase != 'dragging' || _cancel) return;
    StudyStatus? status;
    var insertion = 0;
    for (final s in StudyStatus.values) {
      final i = s.index, rect = _rect(_bodies[i]);
      if (rect == null || !rect.contains(pointer)) continue;
      status = s;
      final localY = pointer.dy - rect.top - _inset + _vertical[i].offset;
      final entries = _entries(s);
      var y = 0.0, normalIndex = 0;
      insertion = _column(s).length;
      for (final row in entries) {
        if (localY < y + _extent) {
          insertion = row.kind == _RowKind.card
              ? normalIndex + (localY > y + _height / 2 ? 1 : 0)
              : row.index;
          break;
        }
        y += _extent;
        if (row.kind == _RowKind.card) normalIndex++;
      }
      break;
    }
    final viewport = _rect(_viewport);
    bool canMove(ScrollController scroll, double at, double min, double max) {
      if (!scroll.hasClients || at < min || at > max) return false;
      return (at < min + 42 && scroll.offset > 0) ||
          (at > max - 42 && scroll.offset < scroll.position.maxScrollExtent);
    }

    var edge =
        viewport != null &&
        viewport.contains(pointer) &&
        canMove(_horizontal, pointer.dx, viewport.left, viewport.right);
    if (status != null) {
      final body = _rect(_bodies[status.index]);
      edge =
          edge ||
          (body != null &&
              canMove(
                _vertical[status.index],
                pointer.dy,
                body.top,
                body.bottom,
              ));
    }
    if (edge && !_edgeTicker.isActive) {
      _lastTick = null;
      _edgeTicker.start();
    }
    if (!edge && _edgeTicker.isActive) _edgeTicker.stop();
    if (status != _target || insertion != _index) {
      setState(() {
        _target = status;
        _index = insertion;
      });
      _message.value = status == null
          ? 'Вне доски · отпустите для отмены'
          : '${_moving!.status.label} → ${status.label} · место ${insertion + 1}';
      if (status != null) HapticFeedback.selectionClick();
    }
  }

  void _edgeScroll(Duration elapsed) {
    if (_phase != 'dragging' || _pointer == null || _cancel) return;
    final dt = _lastTick == null
        ? 1.0
        : ((elapsed - _lastTick!).inMicroseconds / 16667)
              .clamp(0, 2)
              .toDouble();
    _lastTick = elapsed;
    double velocity(double at, double min, double max) {
      const edge = 42.0;
      if (at < min || at > max) return 0;
      if (at < min + edge) return -9 * (1 - (at - min) / edge) * dt;
      if (at > max - edge) return 9 * (1 - (max - at) / edge) * dt;
      return 0;
    }

    void step(ScrollController scroll, double delta) {
      if (!scroll.hasClients || delta == 0) return;
      final next = (scroll.offset + delta)
          .clamp(0, scroll.position.maxScrollExtent)
          .toDouble();
      if (next != scroll.offset) scroll.jumpTo(next);
    }

    final rect = _rect(_viewport), p = _pointer!;
    if (rect == null || !rect.contains(p)) return;
    step(_horizontal, velocity(p.dx, rect.left, rect.right));
    for (final status in StudyStatus.values) {
      final body = _rect(_bodies[status.index]);
      if (body != null && body.contains(p)) {
        step(_vertical[status.index], velocity(p.dy, body.top, body.bottom));
      }
    }
    _update(p);
  }

  List<_BoardRow> _entries(StudyStatus status) {
    final items = _column(status);
    final rows = <_BoardRow>[];
    final moving = _moving;
    for (var i = 0; i <= items.length; i++) {
      final origin =
          moving != null &&
          status == moving.status &&
          i == _originIndex.clamp(0, items.length);
      final target = moving != null && status == _target && i == _index;
      if (origin) rows.add(_BoardRow(moving, _RowKind.origin, i));
      if (target && !(origin && _phase == 'dragging')) {
        rows.add(_BoardRow(moving, _RowKind.slot, i));
      }
      if (i < items.length) rows.add(_BoardRow(items[i], _RowKind.card, i));
    }
    return rows;
  }

  Future<void> _fly(
    Rect? from,
    Rect? to,
    StudyAssignment assignment, {
    bool returning = false,
  }) async {
    if (!mounted ||
        from == null ||
        to == null ||
        StudentMotion.reduced(context)) {
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final origin = overlayBox.globalToLocal(from.topLeft);
    final end = overlayBox.globalToLocal(to.topLeft);
    final controller = AnimationController(
      vsync: this,
      duration: StudentMotion.landing,
    );
    _controllers.add(controller);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: origin.dx,
        top: origin.dy,
        width: _width - 16,
        height: _height,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final t = StudentMotion.curve.transform(controller.value);
                return Transform.translate(
                  offset: (end - origin) * t,
                  child: Transform.rotate(
                    angle: -.012 * (1 - t),
                    child: Transform.scale(
                      alignment: Alignment.topLeft,
                      scale: 1.025 - .025 * t,
                      child: Material(
                        color: Colors.transparent,
                        elevation: 14 * (1 - t),
                        shadowColor: StudentColors.ink,
                        borderRadius: BorderRadius.circular(14),
                        child: _card(
                          assignment,
                          interactive: false,
                          note: returning
                              ? 'Возвращаем на место'
                              : 'Сохраняем…',
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    _flights.add(entry);
    overlay.insert(entry);
    try {
      await controller.forward().orCancel;
    } on TickerCanceled {
      /* disposed */
    }
    if (_flights.remove(entry)) {
      entry.remove();
      entry.dispose();
    }
    if (_controllers.remove(controller)) controller.dispose();
  }

  Future<void> _end(DraggableDetails details) async {
    if (_phase != 'dragging' || _moving == null) return;
    _edgeTicker.stop();
    final assignment = _moving!, status = _target;
    final from =
        (details.offset + const Offset(0, -6)) & Size(_width - 16, _height);
    final same = status == assignment.status && _index == _originIndex;
    if (!details.wasAccepted || status == null || _cancel || same) {
      setState(() {
        _phase = 'returning';
        _target = null;
      });
      await _fly(
        from,
        _rect(_cards[assignment.id]!) ?? _originRect,
        assignment,
        returning: true,
      );
      if (!mounted) return;
      setState(() {
        _moving = null;
        _phase = '';
        _notice = 'Перенос отменён';
      });
      widget.onInteractionChanged?.call(false);
      return;
    }
    await _commit(assignment, status, _index, from: from);
  }

  Future<void> _commit(
    StudyAssignment assignment,
    StudyStatus status,
    int index, {
    Rect? from,
  }) async {
    _message.value = '${assignment.status.label} → ${status.label}';
    final generation = ++_generation;
    final column = _column(status);
    final position = index.clamp(0, column.length);
    final previous = position > 0 ? column[position - 1].id : null;
    final next = position < column.length ? column[position].id : null;
    setState(() {
      _phase = 'landing';
      _target = status;
      _index = position;
    });
    // Attach error handling before awaiting the animation: a fast network failure
    // must never escape as an unhandled asynchronous exception.
    final save = widget.store
        .moveAssignment(
          assignment.id,
          status,
          afterId: previous,
          beforeId: next,
        )
        .then<Object?>((_) => null, onError: (Object error) => error);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final scroll = _vertical[status.index];
    final entries = _entries(status);
    final slotIndex = entries.indexWhere((r) => r.kind == _RowKind.slot);
    if (scroll.hasClients && slotIndex >= 0) {
      final top = slotIndex * _extent;
      final bottom = top + _height;
      final viewport = scroll.position.viewportDimension;
      final offset = top < scroll.offset
          ? top
          : bottom > scroll.offset + viewport
          ? bottom - viewport + 8
          : scroll.offset;
      await scroll.animateTo(
        offset.clamp(0, scroll.position.maxScrollExtent),
        duration: StudentMotion.duration(context, StudentMotion.fast),
        curve: StudentMotion.curve,
      );
    }
    if (!mounted) return;
    await _fly(from, _rect(_slot), assignment);
    if (!mounted || generation != _generation) return;
    setState(() => _phase = 'saving');
    widget.onInteractionChanged?.call(false);
    final error = await save;
    if (!mounted || generation != _generation) return;
    if (error != null) {
      final targetRect = _rect(_slot);
      setState(() {
        _phase = 'returning';
        _target = null;
      });
      if (TickerMode.valuesOf(context).enabled) {
        widget.onInteractionChanged?.call(true);
        await _fly(
          targetRect,
          _rect(_cards[assignment.id]!) ?? _originRect,
          assignment,
          returning: true,
        );
      }
      if (!mounted) return;
      setState(() {
        _moving = null;
        _phase = '';
        _error = 'Не удалось сохранить перенос. Карточка возвращена.';
        _retry = () => _programmatic(assignment.id, status, index: position);
      });
      widget.onInteractionChanged?.call(false);
      return;
    }
    final oldPrev = _oldPrevious, oldNext = _oldNext;
    setState(() {
      _phase = 'accepted';
      _notice = '${assignment.status.label} → ${status.label} · сохранено';
    });
    HapticFeedback.lightImpact();
    final settle = AnimationController(
      vsync: this,
      duration: StudentMotion.duration(context, StudentMotion.normal),
    );
    _controllers.add(settle);
    try {
      await settle.forward().orCancel;
    } on TickerCanceled {
      /* disposed */
    }
    if (_controllers.remove(settle)) settle.dispose();
    if (!mounted || generation != _generation) return;
    setState(() {
      _moving = null;
      _phase = '';
    });
    showStudentMessage(
      context,
      '«${assignment.title}» · ${status.label}',
      action: SnackBarAction(
        label: 'Отменить',
        onPressed: () async {
          try {
            await widget.store.moveAssignment(
              assignment.id,
              assignment.status,
              afterId: oldPrev,
              beforeId: oldNext,
              completedAt: assignment.completedAt,
            );
            if (mounted) setState(() => _notice = 'Перенос отменён');
          } catch (_) {
            if (mounted) {
              setState(
                () => _error = 'Не удалось отменить перенос. Повторите действие через меню карточки.',
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _programmatic(
    String id,
    StudyStatus status, {
    int? index,
  }) async {
    if (_moving != null) return;
    final assignment = widget.store.assignmentById(id);
    if (assignment == null) return;
    _start(assignment);
    _edgeTicker.stop();
    final from = _rect(_cards[id]!);
    _showColumn(status.index);
    // Wait for horizontal reveal before choosing the landing coordinates.
    await Future<void>.delayed(
      StudentMotion.duration(context, StudentMotion.normal),
    );
    if (!mounted) return;
    await _commit(
      assignment,
      status,
      index ?? _column(status).length,
      from: from,
    );
  }

  Widget _card(
    StudyAssignment assignment, {
    bool interactive = true,
    String? note,
    bool accepted = false,
  }) {
    final subject =
        widget.store.subjectById(assignment.subjectId)?.name ?? 'Предмет';
    return Semantics(
      button: interactive,
      label: '${assignment.title}, $subject, ${assignment.status.label}',
      child: SizedBox(
        height: _height,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: accepted ? StudentColors.success : StudentColors.border,
              width: accepted ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: interactive && _moving == null
                ? () =>
                      showStudyAssignment(context, widget.store, assignment.id)
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: StudentColors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    assignment.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      if (note != null) ...[
                        if (accepted)
                          const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: StudentColors.success,
                          )
                        else
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          note ?? studyDeadline(assignment.dueAt),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: accepted
                                ? StudentColors.success
                                : StudentColors.muted,
                          ),
                        ),
                      ),
                      if (interactive)
                        PopupMenuButton<StudyStatus>(
                          enabled: _moving == null,
                          tooltip: 'Переместить ${assignment.title}',
                          icon: const StudentIcon('dots-three', size: 20),
                          onSelected: (status) =>
                              _programmatic(assignment.id, status),
                          itemBuilder: (_) => [
                            for (final status in StudyStatus.values)
                              PopupMenuItem(
                                value: status,
                                child: Text('В «${status.label}»'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ghost(StudyAssignment assignment) => Container(
    height: _height,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .3),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: StudentColors.sand),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.open_with, size: 16, color: StudentColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Исходное место',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          assignment.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: StudentColors.muted,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ],
    ),
  );
  Widget _row(_BoardRow row, double y) {
    final assignment = row.assignment;
    if (row.kind == _RowKind.slot) {
      return Padding(
        key: const ValueKey('insertion-slot'),
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          key: _slot,
          height: _height,
          child: _phase == 'dragging'
              ? Container(
                  key: const ValueKey('board-drop-preview'),
                  decoration: BoxDecoration(
                    color: StudentColors.cream,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: StudentColors.accent, width: 2),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.south, color: StudentColors.accent),
                      const SizedBox(height: 8),
                      Text(
                        'Сюда · ${_target!.label}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Место ${_index + 1}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              : Opacity(
                  opacity: _phase == 'landing' || _phase == 'returning'
                      ? .35
                      : 1,
                  child: _card(
                    assignment,
                    interactive: false,
                    note: _phase == 'accepted' ? 'Сохранено' : 'Сохраняем…',
                    accepted: _phase == 'accepted',
                  ),
                ),
        ),
      );
    }
    final source = row.kind == _RowKind.origin;
    final key = _cards.putIfAbsent(assignment.id, () => GlobalKey());
    return _BoardShift(
      key: ValueKey(assignment.id),
      y: y,
      duration: StudentMotion.duration(context, StudentMotion.normal),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          key: key,
          height: _height,
          child: LongPressDraggable<String>(
            data: assignment.id,
            delay: const Duration(milliseconds: 220),
            maxSimultaneousDrags: _moving == null ? 1 : 0,
            onDragStarted: () => _start(assignment),
            onDragUpdate: (details) => _update(details.globalPosition),
            onDragEnd: _end,
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: _width - 16,
                height: _height,
                child: _LiftedCard(
                  duration: StudentMotion.duration(context, StudentMotion.fast),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _card(assignment, interactive: false),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: -42,
                        child: ValueListenableBuilder<String>(
                          valueListenable: _message,
                          builder: (_, text, _) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: StudentColors.ink,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              text,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            childWhenDragging: _ghost(assignment),
            child: source
                ? AnimatedOpacity(
                    duration: StudentMotion.duration(
                      context,
                      StudentMotion.fast,
                    ),
                    opacity: _phase == 'accepted' ? 0 : 1,
                    child: _ghost(assignment),
                  )
                : _card(assignment),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final allVisible = constraints.maxWidth >= 888;
      return PopScope(
        canPop: _phase != 'dragging',
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _phase == 'dragging') {
            _cancel = true;
            _message.value = 'Перенос отменён · отпустите карточку';
          }
        },
        child: Focus(
          focusNode: _dragFocus,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (_phase == 'dragging') {
                  _cancel = true;
                  _message.value = 'Перенос отменён · отпустите карточку';
                }
              },
            },
            child: Column(
              children: [
                if (_error != null)
                  Material(
                    color: StudentColors.cream.withValues(alpha: .45),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          if (_retry != null)
                            TextButton(
                              onPressed: _moving == null ? _retry : null,
                              child: const Text('Повторить'),
                            ),
                          IconButton(
                            tooltip: 'Закрыть сообщение',
                            onPressed: () => setState(() => _error = null),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: DragTarget<String>(
                    onWillAcceptWithDetails: (details) =>
                        widget.store.assignmentById(details.data) != null &&
                        !_cancel,
                    onAcceptWithDetails: (_) {},
                    builder: (context, _, _) => SizedBox(
                      key: _viewport,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notice) {
                          if (notice.metrics.axis == Axis.horizontal &&
                              _horizontal.hasClients) {
                            final i =
                                (_horizontal.position.maxScrollExtent == 0
                                        ? 0
                                        : _horizontal.offset /
                                              _horizontal
                                                  .position
                                                  .maxScrollExtent *
                                              2)
                                    .round()
                                    .clamp(0, 2);
                            if (i != _visible) setState(() => _visible = i);
                          }
                          return false;
                        },
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          key: const ValueKey('kanban-horizontal'),
                          scrollDirection: Axis.horizontal,
                          physics: _phase == 'dragging'
                              ? const NeverScrollableScrollPhysics()
                              : null,
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final status in StudyStatus.values)
                                Padding(
                                  padding: EdgeInsets.only(
                                    right: status == StudyStatus.done ? 0 : 16,
                                  ),
                                  child: SizedBox(
                                    key: ValueKey(
                                      'kanban-column-${status.name}',
                                    ),
                                    width: _width,
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          height: 48,
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 7,
                                                height: 7,
                                                decoration: BoxDecoration(
                                                  color: studyStatusColor(
                                                    status,
                                                  ),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 9),
                                              Text(
                                                status.label,
                                                style: TextStyle(
                                                  color: studyStatusColor(
                                                    status,
                                                  ),
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 9),
                                              Text(
                                                '${widget.assignments.where((a) => a.status == status).length}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: StudentColors.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: AnimatedContainer(
                                            key: _bodies[status.index],
                                            duration: StudentMotion.duration(
                                              context,
                                              StudentMotion.fast,
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            decoration: BoxDecoration(
                                              color:
                                                  _moving != null &&
                                                      _target == status
                                                  ? StudentColors.cream
                                                  : StudentColors.surface
                                                        .withValues(alpha: .72),
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              border: Border.all(
                                                color:
                                                    _moving != null &&
                                                        _target == status
                                                    ? StudentColors.accent
                                                          .withValues(alpha: .6)
                                                    : Colors.transparent,
                                              ),
                                            ),
                                            child: SingleChildScrollView(
                                              controller:
                                                  _vertical[status.index],
                                              padding: const EdgeInsets.all(
                                                _inset,
                                              ),
                                              child: Column(
                                                children: [
                                                  if (_entries(status).isEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 28,
                                                            horizontal: 16,
                                                          ),
                                                      child: Text(
                                                        _moving == null
                                                            ? 'Здесь пока нет заданий'
                                                            : 'Перетащите задание сюда',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall,
                                                      ),
                                                    ),
                                                  for (final (i, row)
                                                      in _entries(status)
                                                          .indexed)
                                                    _row(row, i * _extent),
                                                ],
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
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Предыдущая колонка',
                          onPressed:
                              _moving == null && !allVisible && _visible > 0
                              ? () => _showColumn(_visible - 1)
                              : null,
                          icon: const Icon(Icons.chevron_left, size: 20),
                        ),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _moving != null
                                  ? (_phase == 'saving'
                                        ? 'Сохраняем перенос…'
                                        : _message.value)
                                  : '${allVisible ? "Все статусы · 3 колонки" : "${StudyStatus.values[_visible].label} · ${_visible + 1} / 3"}${_notice.isEmpty ? "" : "\n$_notice"}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: StudentColors.muted,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Следующая колонка',
                          onPressed:
                              _moving == null && !allVisible && _visible < 2
                              ? () => _showColumn(_visible + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right, size: 20),
                        ),
                      ],
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

enum _RowKind { card, origin, slot }

class _BoardRow {
  const _BoardRow(this.assignment, this.kind, this.index);
  final StudyAssignment assignment;
  final _RowKind kind;
  final int index;
}

/// FLIP-style translation keeps neighbouring cards readable during insertion.
class _BoardShift extends StatefulWidget {
  const _BoardShift({
    super.key,
    required this.y,
    required this.duration,
    required this.child,
  });
  final double y;
  final Duration duration;
  final Widget child;
  @override
  State<_BoardShift> createState() => _BoardShiftState();
}

class _BoardShiftState extends State<_BoardShift>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  double _from = 0;
  double get _offset =>
      _from * (1 - StudentMotion.curve.transform(_controller.value));
  @override
  void didUpdateWidget(covariant _BoardShift oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.y != oldWidget.y) {
      _from = _offset + oldWidget.y - widget.y;
      _controller.duration = widget.duration;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (_, child) =>
        Transform.translate(offset: Offset(0, _offset), child: child),
  );
}

class _LiftedCard extends StatefulWidget {
  const _LiftedCard({required this.child, required this.duration});
  final Widget child;
  final Duration duration;
  @override
  State<_LiftedCard> createState() => _LiftedCardState();
}

class _LiftedCardState extends State<_LiftedCard>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (_, child) {
      final t = StudentMotion.curve.transform(_controller.value);
      return Transform.translate(
        offset: Offset(0, -6 * t),
        child: Transform.rotate(
          angle: -.012 * t,
          child: Transform.scale(
            alignment: Alignment.topLeft,
            scale: 1 + .025 * t,
            child: Material(
              color: Colors.transparent,
              elevation: 16 * t,
              shadowColor: StudentColors.ink.withValues(alpha: .3),
              borderRadius: BorderRadius.circular(14),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
