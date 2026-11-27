import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/lock/app_lock_service.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../motion.dart';

/// Covers the app with a lock screen when app lock is on: when the app
/// opens, and when it comes back after [relockAfter] away. The screens
/// underneath stay as they were, so unlocking returns to the same place.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
    this.relockAfter = const Duration(minutes: 1),
    this.clock = DateTime.now,
  });

  final Widget child;

  /// How long the app can be in the background before it locks again, so
  /// a quick look at a payment app doesn't ask for a fingerprint.
  final Duration relockAfter;

  /// The time now; replaced in tests.
  final DateTime Function() clock;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  /// Null until the setting is read, so nothing shows before it's known.
  bool? _locked;
  bool _enabled = false;
  DateTime? _leftAt;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(appLockProvider, (previous, next) {
      final on = next.value;
      if (on == null) {
        // The setting couldn't be read: open the app rather than lock it out.
        if (next.hasError) setState(() => _locked = false);
        return;
      }
      final first = _locked == null;
      _enabled = on;
      if (first) {
        setState(() => _locked = on);
        if (on) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
      } else if (!on && _locked == true) {
        setState(() => _locked = false);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled || ref.read(appLockServiceProvider).inProgress) return;
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _leftAt ??= widget.clock();
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        if (left != null && _locked == false && widget.clock().difference(left) >= widget.relockAfter) {
          setState(() {
            _locked = true;
            _message = null;
          });
          _unlock();
        }
      case _:
        break;
    }
  }

  Future<void> _unlock() async {
    if (!mounted || _locked != true) return;
    final result = await ref.read(appLockServiceProvider).unlock('Unlock Finance Tracker');
    if (!mounted) return;
    switch (result) {
      case UnlockResult.unlocked:
        setState(() => _locked = false);
      case UnlockResult.noScreenLock:
        // Only someone who could unlock the phone can remove its screen
        // lock, so let them in, and say why the lock is now off.
        await ref.read(appLockProvider.notifier).set(false);
        if (!mounted) return;
        setState(() => _locked = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Your phone has no screen lock now, so app lock was turned off.')),
        );
      case UnlockResult.cancelled:
        setState(() => _message = null);
      case UnlockResult.lockedOut:
        setState(() => _message = 'Too many tries. Wait a moment, then try again.');
      case UnlockResult.failed:
        setState(() => _message = 'The phone couldn\'t check your screen lock. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: locked != false,
          child: TickerMode(enabled: locked == false, child: widget.child),
        ),
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.medium),
          switchInCurve: Motion.curve,
          child: locked == false
              ? const SizedBox.shrink()
              : _LockScreen(key: const ValueKey('lock'), ready: locked == true, message: _message, onUnlock: _unlock),
        ),
      ],
    );
  }
}

/// What shows while the app is locked: the app's name, why it's locked and
/// one button to try again.
class _LockScreen extends StatelessWidget {
  const _LockScreen({super.key, required this.ready, required this.message, required this.onUnlock});

  /// False while the setting is still being read: show only the background.
  final bool ready;
  final String? message;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      child: !ready
          ? const SizedBox.expand()
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: FadeIn(
                  child: Column(
                    children: [
                      const Spacer(flex: 3),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: AppIcon(AppIcons.lock, size: 32, color: scheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: 24),
                      Text('Finance Tracker is locked', style: text.titleLarge, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(
                        message ?? 'Use your fingerprint or your phone\'s PIN to open it.',
                        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(flex: 4),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onUnlock,
                          icon: const AppIcon(AppIcons.fingerprint, size: 20),
                          label: const Text('Unlock'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
