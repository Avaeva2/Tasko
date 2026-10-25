import 'student_models.dart';

const _digits =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/// Legacy assignments retain deadline ordering until explicitly moved.
String studyBoardOrder(StudyAssignment assignment) {
  if (assignment.boardOrder case final String value) return value;
  var value = assignment.dueAt.millisecondsSinceEpoch + 8640000000000000;
  var encoded = '';
  do {
    encoded = _digits[value % 62] + encoded;
    value ~/= 62;
  } while (value > 0);
  return 'U${encoded.padLeft(10, '0')}${assignment.id.replaceAll('-', '')}V';
}

int compareStudyBoard(StudyAssignment a, StudyAssignment b) {
  final rank = studyBoardOrder(a).compareTo(studyBoardOrder(b));
  return rank == 0 ? a.id.compareTo(b.id) : rank;
}

/// Dense lexicographic positions avoid float precision loss during repeated
/// insertions. Generated keys never end in the minimum digit.
String studyBoardBetween(String? left, String? right) {
  if (left != null && right != null && left.compareTo(right) >= 0) {
    throw ArgumentError('Некорректные соседние позиции.');
  }
  var prefix = '';
  for (var index = 0; ; index++) {
    final low = left != null && index < left.length
        ? _digits.indexOf(left[index])
        : 0;
    final high = right != null && index < right.length
        ? _digits.indexOf(right[index])
        : 61;
    if (low < 0 || high < 0) throw ArgumentError('Некорректная позиция.');
    if (high - low > 1) return prefix + _digits[(low + high) ~/ 2];
    prefix += _digits[low];
    if (low != high) right = null;
  }
}
