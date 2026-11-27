import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/capture/notification_parser.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../motion.dart';
import 'captured_payments_page.dart';

/// Turns payment capture on or off and picks which apps it listens to.
class CaptureSettingsPage extends ConsumerStatefulWidget {
  const CaptureSettingsPage({super.key});

  @override
  ConsumerState<CaptureSettingsPage> createState() => _CaptureSettingsPageState();
}

class _CaptureSettingsPageState extends ConsumerState<CaptureSettingsPage> with WidgetsBindingObserver {
  bool? _enabled;
  Set<String> _packages = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Reads the switch again on return from Android's settings screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final channel = ref.read(captureChannelProvider);
    final enabled = await channel.isEnabled();
    final packages =
        await channel.packages() ??
        {
          for (final s in PaymentSource.all)
            if (s.onByDefault) s.package,
        };
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _packages = packages;
      });
    }
  }

  Future<void> _toggle(PaymentSource s, bool on) async {
    setState(() => on ? _packages.add(s.package) : _packages.remove(s.package));
    await ref.read(captureChannelProvider).setPackages(_packages);
  }

  @override
  Widget build(BuildContext context) {
    final channel = ref.watch(captureChannelProvider);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final enabled = _enabled;

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(title, style: t.titleSmall?.copyWith(color: scheme.primary)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Payment capture')),
      body: !channel.supported
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  channel.included
                      ? 'Payment capture works on Android only.'
                      : 'This is the lite build, which leaves out payment capture so it installs from anywhere. '
                            'Install the full build over USB to capture payments. Your entries stay.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : enabled == null
          ? const AppLoader()
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Card.filled(
                    color: enabled ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AppIcon(
                                enabled ? AppIcons.done : AppIcons.notificationOff,
                                color: enabled ? scheme.onPrimaryContainer : muted,
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(enabled ? 'Capture is on' : 'Capture is off', style: t.titleMedium)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            enabled
                                ? 'Payments from the apps below wait under Captured payments until you add them.'
                                : 'Allow notification access for Finance Tracker. Payments from the apps below will then '
                                      'wait in the app for you to add.',
                            style: t.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          if (enabled)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context)
                                          .push(MaterialPageRoute<void>(builder: (_) => const CapturedPaymentsPage())),
                                  child: const Text('See captured payments'),
                                ),
                                OutlinedButton(
                                  onPressed: channel.openSettings,
                                  child: const Text('Turn off in Android settings'),
                                ),
                              ],
                            )
                          else
                            FilledButton(
                              onPressed: channel.openSettings,
                              child: const Text('Allow notification access'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!enabled)
                  const ListTile(
                    leading: AppIcon(AppIcons.privacy),
                    title: Text('Switch greyed out?'),
                    subtitle: Text(
                      'Android blocks this for apps installed from an APK. Open App info for Finance Tracker, '
                      'tap the three-dot menu at the top, choose Allow restricted settings, then try again.',
                    ),
                  ),
                section('UPI apps'),
                for (final s in PaymentSource.all.where((s) => !s.sms))
                  SwitchListTile(
                    title: Text(s.label),
                    value: _packages.contains(s.package),
                    onChanged: (v) => _toggle(s, v),
                  ),
                section('Bank SMS'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'Banks text every debit and credit, so this also catches card and net-banking payments. '
                    'Only messages that name an account or card and a reference are kept.',
                    style: t.bodySmall?.copyWith(color: muted),
                  ),
                ),
                for (final s in PaymentSource.all.where((s) => s.sms))
                  SwitchListTile(
                    title: Text(s.label),
                    value: _packages.contains(s.package),
                    onChanged: (v) => _toggle(s, v),
                  ),
                section('Good to know'),
                const ListTile(
                  leading: AppIcon(AppIcons.phone),
                  title: Text('Stays on this phone'),
                  subtitle: Text(
                    'Only notifications from the apps switched on here, and only ones that mention an amount, are read. '
                    'OTPs are dropped before anything is stored.',
                  ),
                ),
                const ListTile(
                  leading: AppIcon(AppIcons.notificationPaused),
                  title: Text('Some payments send no notification'),
                  subtitle: Text(
                    'UPI apps do not always notify for money you send. Turning on bank SMS covers those, '
                    'and the same payment seen twice is flagged so you add it once.',
                  ),
                ),
              ],
            ),
    );
  }
}
