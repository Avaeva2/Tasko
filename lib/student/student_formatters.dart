import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'student_models.dart';
import 'student_theme.dart';

String studyTime(DateTime value) => DateFormat('HH:mm').format(value);
String studyDate(DateTime value) => DateFormat('d MMMM', 'ru').format(value);
String studyDeadline(DateTime value, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final difference = DateUtils.dateOnly(value).difference(today).inDays;
  final day = difference == 0
      ? 'Сегодня'
      : difference == 1
      ? 'Завтра'
      : studyDate(value);
  return '$day, ${studyTime(value)}';
}

Color studyStatusColor(StudyStatus status) => status == StudyStatus.done
    ? StudentColors.success
    : status == StudyStatus.inProgress
    ? StudentColors.accent
    : StudentColors.muted;
