import 'package:flutter/material.dart';

abstract final class StudentMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 220);
  static const route = Duration(milliseconds: 260);
  static const landing = Duration(milliseconds: 280);
  static const curve = Curves.easeOutCubic;
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
  static Duration duration(BuildContext context, Duration value) =>
      reduced(context) ? Duration.zero : value;
}

class StudentRoute<T> extends MaterialPageRoute<T> {
  StudentRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });
  @override
  Duration get transitionDuration => StudentMotion.route;
  @override
  Duration get reverseTransitionDuration => StudentMotion.normal;
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => StudentMotion.reduced(context)
      ? child
      : super.buildTransitions(context, animation, secondaryAnimation, child);
}

class StudentLocationTitle extends StatelessWidget {
  const StudentLocationTitle(this.title, {super.key, required this.location});
  final String title, location;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        location,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 2),
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    ],
  );
}

/// Keeps each section's form, filters and scroll controllers alive while its
/// entry transition runs. The outgoing section is hidden immediately, so text
/// from two sections can never paint on top of each other, even on rapid taps.
class StudentSectionScene extends StatefulWidget {
  const StudentSectionScene({
    super.key,
    required this.active,
    required this.direction,
    required this.child,
  });
  final bool active;
  final int direction;
  final Widget child;
  @override
  State<StudentSectionScene> createState() => _StudentSectionSceneState();
}

class _StudentSectionSceneState extends State<StudentSectionScene>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: StudentMotion.normal,
    value: widget.active ? 1 : 0,
  );
  double _direction = 1;
  @override
  void didUpdateWidget(covariant StudentSectionScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      _direction = widget.direction.toDouble();
      _controller.stop();
      if (!widget.active) {
        _controller.value = 0;
      } else if (StudentMotion.reduced(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
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
    child: FocusScope(
      canRequestFocus: widget.active,
      descendantsAreFocusable: widget.active,
      child: widget.child,
    ),
    builder: (context, child) {
      final value = StudentMotion.curve.transform(_controller.value);
      return Offstage(
        offstage: !widget.active,
        child: TickerMode(
          enabled: widget.active,
          child: IgnorePointer(
            ignoring: !widget.active,
            child: ExcludeSemantics(
              excluding: !widget.active,
              child: Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(
                    StudentMotion.reduced(context)
                        ? 0
                        : _direction * 14 * (1 - value),
                    0,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
