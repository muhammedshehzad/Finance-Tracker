import 'package:material_ui/material_ui.dart';

import '../core/money.dart';

/// Shared timing, so everything in the app moves at the same pace. Every
/// duration drops to zero when the phone's "Remove animations" setting is on.
abstract final class Motion {
  static const short = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
  static const long = Duration(milliseconds: 650);
  static const curve = Curves.easeOutCubic;

  static Duration of(BuildContext context, Duration duration) =>
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : duration;
}

/// The one loading indicator used everywhere: a thin, round-capped spinner,
/// centred unless [centered] is false (for buttons and dialogs).
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.size = 28, this.centered = true, this.color});

  final double size;
  final bool centered;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final spinner = SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(strokeWidth: size < 24 ? 2 : 3, strokeCap: StrokeCap.round, color: color),
    );
    return centered ? Center(child: spinner) : spinner;
  }
}

/// Fades its child in and lifts it slightly, once, when it first appears.
class FadeIn extends StatefulWidget {
  const FadeIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late final _curved = CurvedAnimation(parent: _controller, curve: Motion.curve);
  late final _offset = Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(_curved);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    final duration = Motion.of(context, Motion.medium);
    if (duration == Duration.zero) {
      _controller.value = 1;
      return;
    }
    _controller.duration = duration + widget.delay;
    final start = widget.delay.inMicroseconds / _controller.duration!.inMicroseconds;
    _curved.curve = Interval(start, 1, curve: Motion.curve);
    _controller.forward();
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curved,
    child: SlideTransition(position: _offset, child: widget.child),
  );
}

/// An amount that rolls smoothly to its new value when it changes, such as
/// when the month is switched. Shows whole rupees while moving.
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney(this.value, {super.key, this.style, this.signed = false});

  final int value;
  final TextStyle? style;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: Motion.of(context, Motion.long),
      curve: Motion.curve,
      builder: (context, v, _) {
        final shown = v.round() == value ? value : (v / 100).round() * 100;
        return Text(formatMoney(shown, signed: signed), style: style);
      },
    );
  }
}

/// A rounded progress bar that grows to [value] when it appears and slides
/// to new values after.
class AnimatedBar extends StatelessWidget {
  const AnimatedBar({
    super.key,
    required this.value,
    required this.color,
    required this.backgroundColor,
    this.height = 4,
  });

  final double value;
  final Color color;
  final Color backgroundColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: Motion.of(context, Motion.long),
        curve: Motion.curve,
        builder: (context, v, _) =>
            LinearProgressIndicator(value: v, minHeight: height, color: color, backgroundColor: backgroundColor),
      ),
    );
  }
}

/// Cross-fades between two versions of a small piece of content, such as a
/// month name or a button label, keyed by [value].
class SwapIn<T> extends StatelessWidget {
  const SwapIn({super.key, required this.value, required this.child, this.alignment = Alignment.center});

  final T value;
  final Widget child;

  /// Where the content sits in the space it is given.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.short),
      switchInCurve: Motion.curve,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(animation), child: child),
      ),
      child: KeyedSubtree(key: ValueKey(value), child: child),
    );
  }
}
