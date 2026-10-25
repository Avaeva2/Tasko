import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'student_theme.dart';
import 'student_motion.dart';
export 'student_motion.dart';

class StudentBrand extends StatelessWidget {
  const StudentBrand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.asset(
          'assets/student/tasko-logo.png',
          width: 34,
          height: 34,
          excludeFromSemantics: true,
        ),
      ),
      const SizedBox(width: 10),
      const Flexible(
        child: Text(
          'Tasko',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class StudentIcon extends StatelessWidget {
  const StudentIcon(this.name, {super.key, this.size = 24, this.color});
  final String name;
  final double size;
  final Color? color;
  static Future<Map<String, dynamic>>? _icons;
  static Future<Map<String, dynamic>> _load() => _icons ??= rootBundle
      .loadString('assets/student/icon-map.json')
      .then((value) => jsonDecode(value) as Map<String, dynamic>)
      .catchError((Object _) => <String, dynamic>{});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: FutureBuilder<Map<String, dynamic>>(
      future: _load(),
      builder: (context, snapshot) {
        final path = snapshot.data?[name] as String?;
        if (path != null) {
          return SvgPicture.asset(
            path.startsWith('assets/') ? path : 'assets/student/$path',
            width: size,
            height: size,
            colorFilter: ColorFilter.mode(
              color ?? StudentColors.ink,
              BlendMode.srcIn,
            ),
          );
        }
        final fallback = <String, IconData>{
          'calendar-blank': Icons.calendar_today_outlined,
          'squares-four': Icons.dashboard_outlined,
          'graduation-cap': Icons.school_outlined,
          'user-circle': Icons.account_circle_outlined,
          'bell-simple': Icons.notifications_none,
          'plus': Icons.add,
          'caret-right': Icons.chevron_right,
          'arrow-left': Icons.arrow_back,
          'check-circle': Icons.check_circle_outline,
          'check': Icons.check,
          'book-open': Icons.menu_book_outlined,
          'sliders-horizontal': Icons.tune,
          'list-bullets': Icons.list,
          'clock': Icons.schedule,
          'map-pin': Icons.location_on_outlined,
          'file-pdf': Icons.picture_as_pdf_outlined,
          'paperclip': Icons.attach_file,
          'dots-three': Icons.more_horiz,
          'pencil-simple': Icons.edit_outlined,
          'arrow-right': Icons.arrow_forward,
          'envelope-simple': Icons.mail_outline,
          'lock-key': Icons.lock_outline,
          'trash': Icons.delete_outline,
        };
        return Icon(
          fallback[name] ?? Icons.circle_outlined,
          size: size,
          color: color ?? StudentColors.ink,
        );
      },
    ),
  );
}

class StudentButton extends StatelessWidget {
  const StudentButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.outlined = false,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final bool outlined;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (icon != null)
          StudentIcon(
            icon!,
            size: 20,
            color: outlined ? StudentColors.accent : Colors.white,
          ),
        if (busy || icon != null) const SizedBox(width: 10),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    return Semantics(
      button: true,
      label: label,
      enabled: !busy && onPressed != null,
      onTap: busy ? null : onPressed,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        child: outlined
            ? OutlinedButton(onPressed: busy ? null : onPressed, child: content)
            : FilledButton(onPressed: busy ? null : onPressed, child: content),
      ),
    );
  }
}

class StudentBadge extends StatelessWidget {
  const StudentBadge(this.label, {super.key, this.color, this.background});
  final String label;
  final Color? color;
  final Color? background;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background ?? StudentColors.cream.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color ?? StudentColors.accent,
      ),
    ),
  );
}

class StudentPage extends StatelessWidget {
  const StudentPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.bottom,
    this.location,
  });
  final String? location;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: location == null ? null : 70,
      title: location == null
          ? Text(title)
          : StudentLocationTitle(title, location: location!),
      actions: actions,
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: child,
      ),
    ),
    bottomNavigationBar: bottom == null
        ? null
        : SafeArea(
            top: false,
            child: Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: bottom,
                ),
              ),
            ),
          ),
  );
}

class StudentEmpty extends StatelessWidget {
  const StudentEmpty({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StudentIcon('book-open', size: 38, color: StudentColors.muted),
        const SizedBox(height: 20),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(color: StudentColors.muted, height: 1.6),
        ),
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    ),
  );
}

class StudentFieldLabel extends StatelessWidget {
  const StudentFieldLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: StudentColors.muted,
      ),
    ),
  );
}

/// Student action notices are transient, including notices with an Undo action.
/// Flutter otherwise makes action snackbars persistent by default.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showStudentMessage(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.removeCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      persist: false,
      duration: Duration(seconds: action == null ? 3 : 5),
      showCloseIcon: true,
    ),
  );
}

Future<void> studentGuard(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      showStudentMessage(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
}
