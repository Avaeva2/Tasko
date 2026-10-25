import 'package:flutter/material.dart';

import '../data/tasko_store.dart';
import '../models.dart';
import 'core_screens.dart' show showTaskEditor;
import 'task_detail_screen.dart';

/// Explicit navigation for the retained project-management implementation.
Future<void> showTaskDetails(
  BuildContext context,
  TaskoStore store, {
  required TaskoTask task,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => TaskDetailScreen(
      store: store,
      taskId: task.id,
      onEdit: (context, task) => showTaskEditor(context, store, task: task),
    ),
  ),
);
