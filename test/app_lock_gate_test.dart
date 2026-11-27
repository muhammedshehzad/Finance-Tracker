import 'package:finance_tracker/services/lock/app_lock_service.dart';
import 'package:finance_tracker/state/providers.dart';
import 'package:finance_tracker/ui/lock/app_lock_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Answers unlock prompts from a list, and counts them.
class FakeLock extends AppLockService {
  FakeLock(this.answers);

  final List<UnlockResult> answers;
  int asked = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<UnlockResult> unlock(String reason) async {
    asked++;
    return answers.isEmpty ? UnlockResult.cancelled : answers.removeAt(0);
  }
}

/// The lock setting without a database.
class FakeSetting extends AppLockSetting {
  FakeSetting(this.initial);

  final bool initial;

  @override
  Future<bool> build() async => initial;

  @override
  Future<void> set(bool on) async => state = AsyncData(on);
}

void main() {
  late DateTime now;
  late ProviderContainer container;

  Future<FakeLock> pump(WidgetTester tester, {required bool on, List<UnlockResult> answers = const []}) async {
    now = DateTime(2026, 11, 27, 9);
    final lock = FakeLock([...answers]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockServiceProvider.overrideWithValue(lock),
          appLockProvider.overrideWith(() => FakeSetting(on)),
        ],
        child: MaterialApp(
          builder: (context, child) => AppLockGate(clock: () => now, child: child!),
          home: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(tester.element(find.byType(AppLockGate)));
    return lock;
  }

  void cycle(WidgetTester tester, AppLifecycleState state) => tester.binding.handleAppLifecycleStateChanged(state);

  testWidgets('opens straight away when the lock is off', (tester) async {
    final lock = await pump(tester, on: false);
    expect(find.text('Finance Tracker is locked'), findsNothing);
    expect(lock.asked, 0);
  });

  testWidgets('asks on open, and the Unlock button asks again after a cancel', (tester) async {
    final lock = await pump(tester, on: true, answers: [UnlockResult.cancelled, UnlockResult.unlocked]);
    expect(lock.asked, 1);
    expect(find.text('Finance Tracker is locked'), findsOneWidget);

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(lock.asked, 2);
    expect(find.text('Finance Tracker is locked'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('locks again only after a minute away', (tester) async {
    final lock = await pump(tester, on: true, answers: [UnlockResult.unlocked, UnlockResult.unlocked]);
    expect(find.text('Finance Tracker is locked'), findsNothing);

    cycle(tester, AppLifecycleState.inactive);
    cycle(tester, AppLifecycleState.hidden);
    cycle(tester, AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 30));
    cycle(tester, AppLifecycleState.hidden);
    cycle(tester, AppLifecycleState.inactive);
    cycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(lock.asked, 1, reason: 'a quick look elsewhere does not lock');

    cycle(tester, AppLifecycleState.inactive);
    cycle(tester, AppLifecycleState.hidden);
    cycle(tester, AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    cycle(tester, AppLifecycleState.hidden);
    cycle(tester, AppLifecycleState.inactive);
    cycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(lock.asked, 2);
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('lets the owner in and turns the lock off when the phone lost its screen lock', (tester) async {
    await pump(tester, on: true, answers: [UnlockResult.noScreenLock]);
    expect(find.text('Finance Tracker is locked'), findsNothing);
    expect(container.read(appLockProvider).value, isFalse);
  });

  testWidgets('says to wait after too many tries', (tester) async {
    await pump(tester, on: true, answers: [UnlockResult.lockedOut]);
    expect(find.text('Too many tries. Wait a moment, then try again.'), findsOneWidget);
  });
}
