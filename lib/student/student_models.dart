import 'dart:convert';
import 'dart:typed_data';

const _unset = Object();

enum StudyStatus {
  todo,
  inProgress,
  done;

  String get label => switch (this) {
    todo => 'Сделать',
    inProgress => 'В работе',
    done => 'Готово',
  };
}

class StudySubject {
  const StudySubject({
    required this.id,
    required this.name,
    this.teacher = '',
    this.color = 0xff6D2932,
  });
  final String id, name, teacher;
  final int color;
  StudySubject copyWith({String? name, String? teacher, int? color}) =>
      StudySubject(
        id: id,
        name: name ?? this.name,
        teacher: teacher ?? this.teacher,
        color: color ?? this.color,
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'teacher': teacher,
    'color': color,
  };
  factory StudySubject.fromJson(Map<String, dynamic> j) => StudySubject(
    id: j['id'],
    name: j['name'],
    teacher: j['teacher'] ?? '',
    color: j['color'] ?? 0xff6D2932,
  );
}

class StudyClass {
  const StudyClass({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.room = '',
    this.teacher = '',
  });
  final String id, subjectId, title, room, teacher;
  final DateTime startsAt, endsAt;
  StudyClass copyWith({
    String? subjectId,
    String? title,
    String? room,
    String? teacher,
    DateTime? startsAt,
    DateTime? endsAt,
  }) => StudyClass(
    id: id,
    subjectId: subjectId ?? this.subjectId,
    title: title ?? this.title,
    room: room ?? this.room,
    teacher: teacher ?? this.teacher,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt ?? this.endsAt,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'subjectId': subjectId,
    'title': title,
    'room': room,
    'teacher': teacher,
    'startsAt': startsAt.toIso8601String(),
    'endsAt': endsAt.toIso8601String(),
  };
  factory StudyClass.fromJson(Map<String, dynamic> j) => StudyClass(
    id: j['id'],
    subjectId: j['subjectId'],
    title: j['title'],
    room: j['room'] ?? '',
    teacher: j['teacher'] ?? '',
    startsAt: DateTime.parse(j['startsAt']),
    endsAt: DateTime.parse(j['endsAt']),
  );
}

class StudyChecklistItem {
  const StudyChecklistItem({
    required this.id,
    required this.title,
    this.done = false,
  });
  final String id, title;
  final bool done;
  StudyChecklistItem copyWith({String? title, bool? done}) =>
      StudyChecklistItem(
        id: id,
        title: title ?? this.title,
        done: done ?? this.done,
      );
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};
  factory StudyChecklistItem.fromJson(Map<String, dynamic> j) =>
      StudyChecklistItem(
        id: j['id'],
        title: j['title'],
        done: j['done'] ?? false,
      );
}

/// Local demo stores bytes as base64; cloud stores only a private Storage path.
class StudyMaterial {
  const StudyMaterial({
    required this.id,
    required this.name,
    this.url,
    this.bytes,
    this.mimeType,
    this.storagePath,
    this.byteLength,
  });
  final String id, name;
  final String? url, mimeType, storagePath;
  final Uint8List? bytes;
  final int? byteLength;
  int get size => bytes?.length ?? byteLength ?? 0;
  int get byteSize => size;
  bool get isLink => url != null;
  StudyMaterial copyWith({
    String? name,
    Object? url = _unset,
    Object? bytes = _unset,
    Object? mimeType = _unset,
    Object? storagePath = _unset,
    int? byteLength,
  }) => StudyMaterial(
    id: id,
    name: name ?? this.name,
    url: identical(url, _unset) ? this.url : url as String?,
    bytes: identical(bytes, _unset) ? this.bytes : bytes as Uint8List?,
    mimeType: identical(mimeType, _unset) ? this.mimeType : mimeType as String?,
    storagePath: identical(storagePath, _unset)
        ? this.storagePath
        : storagePath as String?,
    byteLength: byteLength ?? this.byteLength,
  );
  Map<String, dynamic> toJson({bool includeBytes = true}) => {
    'id': id,
    'name': name,
    'url': url,
    'bytes': includeBytes && bytes != null ? base64Encode(bytes!) : null,
    'mimeType': mimeType,
    'storagePath': storagePath,
    'byteLength': size,
  };
  factory StudyMaterial.fromJson(Map<String, dynamic> j) => StudyMaterial(
    id: j['id'],
    name: j['name'],
    url: j['url'],
    bytes: j['bytes'] != null ? base64Decode(j['bytes']) : null,
    mimeType: j['mimeType'],
    storagePath: j['storagePath'],
    byteLength: j['byteLength'],
  );
}

class StudyAssignment {
  const StudyAssignment({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.dueAt,
    this.description = '',
    this.classId,
    this.status = StudyStatus.todo,
    this.reminderMinutes = 1440,
    this.checklist = const [],
    this.materials = const [],
    this.completedAt,
    this.boardOrder,
  });
  final String id, subjectId, title, description;
  final String? classId;
  final StudyStatus status;
  final DateTime dueAt;
  final DateTime? completedAt;
  final String? boardOrder;
  final int? reminderMinutes;
  final List<StudyChecklistItem> checklist;
  final List<StudyMaterial> materials;
  DateTime? get reminderAt =>
      reminderMinutes == null || status == StudyStatus.done
      ? null
      : dueAt.subtract(Duration(minutes: reminderMinutes!));
  bool get isOverdue =>
      status != StudyStatus.done && dueAt.isBefore(DateTime.now());
  StudyAssignment copyWith({
    String? title,
    String? subjectId,
    String? description,
    DateTime? dueAt,
    StudyStatus? status,
    Object? classId = _unset,
    Object? reminderMinutes = _unset,
    Object? completedAt = _unset,
    Object? boardOrder = _unset,
    List<StudyChecklistItem>? checklist,
    List<StudyMaterial>? materials,
  }) => StudyAssignment(
    id: id,
    subjectId: subjectId ?? this.subjectId,
    title: title ?? this.title,
    description: description ?? this.description,
    dueAt: dueAt ?? this.dueAt,
    status: status ?? this.status,
    classId: identical(classId, _unset) ? this.classId : classId as String?,
    reminderMinutes: identical(reminderMinutes, _unset)
        ? this.reminderMinutes
        : reminderMinutes as int?,
    completedAt: identical(completedAt, _unset)
        ? this.completedAt
        : completedAt as DateTime?,
    boardOrder: identical(boardOrder, _unset)
        ? this.boardOrder
        : boardOrder as String?,
    checklist: checklist ?? this.checklist,
    materials: materials ?? this.materials,
  );
  Map<String, dynamic> toJson({bool includeBytes = true}) => {
    'id': id,
    'subjectId': subjectId,
    'title': title,
    'description': description,
    'classId': classId,
    'status': status.name,
    'dueAt': dueAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    if (boardOrder != null) 'boardOrder': boardOrder,
    'reminderMinutes': reminderMinutes,
    'checklist': checklist.map((e) => e.toJson()).toList(),
    'materials': materials
        .map((e) => e.toJson(includeBytes: includeBytes))
        .toList(),
  };
  factory StudyAssignment.fromJson(Map<String, dynamic> j) => StudyAssignment(
    id: j['id'],
    subjectId: j['subjectId'],
    title: j['title'],
    description: j['description'] ?? '',
    classId: j['classId'],
    status: StudyStatus.values.byName(j['status'] ?? 'todo'),
    dueAt: DateTime.parse(j['dueAt']),
    completedAt: j['completedAt'] == null
        ? null
        : DateTime.parse(j['completedAt']),
    boardOrder:
        j['boardOrder'] is String &&
            RegExp(r'^[0-9A-Za-z]*[1-9A-Za-z]$').hasMatch(j['boardOrder'])
        ? j['boardOrder']
        : null,
    reminderMinutes: j['reminderMinutes'],
    checklist: (j['checklist'] as List? ?? [])
        .map((e) => StudyChecklistItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    materials: (j['materials'] as List? ?? [])
        .map((e) => StudyMaterial.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

class StudyProfile {
  const StudyProfile({
    this.name = '',
    this.email = '',
    this.group = '',
    this.course = 1,
    this.subgroup = 1,
  });
  final String name, email, group;
  final int course, subgroup;
  StudyProfile copyWith({
    String? name,
    String? email,
    String? group,
    int? course,
    int? subgroup,
  }) => StudyProfile(
    name: name ?? this.name,
    email: email ?? this.email,
    group: group ?? this.group,
    course: course ?? this.course,
    subgroup: subgroup ?? this.subgroup,
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'group': group,
    'course': course,
    'subgroup': subgroup,
  };
  factory StudyProfile.fromJson(Map<String, dynamic> j) => StudyProfile(
    name: j['name'] ?? '',
    email: j['email'] ?? '',
    group: j['group'] ?? '',
    course: j['course'] ?? 1,
    subgroup: j['subgroup'] ?? 1,
  );
}
