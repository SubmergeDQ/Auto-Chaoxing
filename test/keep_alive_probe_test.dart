// 保活自检的判定逻辑：这里判错了会误导用户以为熄屏可用，所以逐条钉住。
//
// 注意不能用 tester.runAsync：那会切到真实异步区，Timer.periodic 变成真定时器，
// tester.pump 就推不动它了。让 start() 直接跑在 testWidgets 的假时钟里才对。
import 'dart:async';

import 'package:auto_chaoxing/state/keep_alive_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_run_keeper.dart';

void main() {
  /// 推进墙钟并让定时器走一拍。两者必须一起动，否则测不出「回调被押后」。
  Future<void> beat(WidgetTester tester, void Function(Duration) advance,
      {Duration step = const Duration(seconds: 15), Duration? actualGap}) async {
    advance(actualGap ?? step);
    await tester.pump(step);
  }

  testWidgets('心跳连贯时判定为计时连续', (WidgetTester tester) async {
    DateTime now = DateTime(2026, 11, 12, 20);
    final RunKeeperStub keeper = RunKeeperStub();
    final KeepAliveProbe probe = KeepAliveProbe(keeper: keeper, clock: () => now);

    unawaited(probe.start());
    await tester.pump();

    for (int i = 0; i < 12; i++) {
      await beat(tester, (Duration d) => now = now.add(d));
    }

    expect(probe.phase, ProbePhase.done);
    expect(probe.ticks, 12);
    expect(probe.maxGap, const Duration(seconds: 15));
    expect(probe.continuous, isTrue);
    // 结束时要把前台服务撤掉，别留一条常驻通知。
    expect(keeper.endCalls, 1);
    probe.dispose();
  });

  testWidgets('中间被系统押后一次，判定为中断', (WidgetTester tester) async {
    DateTime now = DateTime(2026, 11, 12, 20);
    final RunKeeperStub keeper = RunKeeperStub();
    final KeepAliveProbe probe = KeepAliveProbe(keeper: keeper, clock: () => now);

    unawaited(probe.start());
    await tester.pump();

    // 前 5 次正常。
    for (int i = 0; i < 5; i++) {
      await beat(tester, (Duration d) => now = now.add(d));
    }
    // 熄屏被冻住：墙钟走了 75 秒，才轮到一次回调。
    await beat(
      tester,
      (Duration d) => now = now.add(d),
      actualGap: const Duration(seconds: 75),
    );
    // 恢复后继续走完。
    for (int i = 0; i < 6; i++) {
      await beat(tester, (Duration d) => now = now.add(d));
    }

    expect(probe.phase, ProbePhase.done);
    expect(probe.maxGap, const Duration(seconds: 75));
    expect(probe.continuous, isFalse);
    expect(probe.verdict, contains('最长间隔 75 秒'));
    probe.dispose();
  });

  testWidgets('保活起不来时如实标记，不假称已挂上', (WidgetTester tester) async {
    DateTime now = DateTime(2026, 11, 12, 20);
    final RunKeeperStub keeper = RunKeeperStub(beginResult: false);
    final KeepAliveProbe probe = KeepAliveProbe(keeper: keeper, clock: () => now);

    unawaited(probe.start());
    await tester.pump();
    expect(probe.keeping, isFalse);

    for (int i = 0; i < 12; i++) {
      await beat(tester, (Duration d) => now = now.add(d));
    }

    expect(probe.phase, ProbePhase.done);
    // 没起来就没有服务可撤。
    expect(keeper.endCalls, 0);
    // 也不该对没起的服务刷通知。
    expect(keeper.updateCalls, 0);
    probe.dispose();
  });

  testWidgets('中途停止会撤掉服务并回到未开始', (WidgetTester tester) async {
    DateTime now = DateTime(2026, 11, 12, 20);
    final RunKeeperStub keeper = RunKeeperStub();
    final KeepAliveProbe probe = KeepAliveProbe(keeper: keeper, clock: () => now);

    unawaited(probe.start());
    await tester.pump();
    for (int i = 0; i < 3; i++) {
      await beat(tester, (Duration d) => now = now.add(d));
    }

    unawaited(probe.stop());
    await tester.pump();

    expect(probe.phase, ProbePhase.idle);
    expect(probe.ticks, 0);
    expect(keeper.endCalls, 1);
    probe.dispose();
  });
}
