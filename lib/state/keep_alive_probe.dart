// 后台保活自检：不需要账号，就能验证「熄屏之后计时还在不在走」。
//
// 做法是纯本地计时，不发任何网络请求：
//   每 15 秒一次心跳，记下每次回调的墙钟时间，回来时看最长的那次间隔。
//   如果熄屏期间系统把进程冻住，Timer 回调会被推迟到亮屏那一刻，
//   间隔就会出现几十秒甚至几分钟的空档 —— 真实执行时，这正好表现为「上报丢了」。
//
// 为什么用墙钟差而不是「有没有收到回调」：进程被冻结时回调队列不会消失，
// 只是被一起押后；只有比较时间戳才看得出中间断过。
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/platform_services.dart';

enum ProbePhase { idle, running, done }

class KeepAliveProbe extends ChangeNotifier {
  KeepAliveProbe({
    RunKeeper? keeper,
    this.total = const Duration(minutes: 3),
    this.step = const Duration(seconds: 15),
    DateTime Function()? clock,
  })  : _keeper = keeper ?? const NoopRunKeeper(),
        _now = clock ?? DateTime.now;

  final RunKeeper _keeper;

  /// 墙钟。测试里注入假时钟，才能造出「回调被押后」的场景。
  final DateTime Function() _now;

  /// 自检总时长。三分种足够覆盖一次 Doze 进入判定，又不至于让人等太久。
  final Duration total;

  /// 心跳间隔。
  final Duration step;

  ProbePhase phase = ProbePhase.idle;

  /// 实际收到的回调次数。
  int ticks = 0;

  /// 按墙钟算，这段时间本该有的次数。
  int expectedTicks = 0;

  /// 相邻两次心跳之间最长的墙钟间隔。判定是否被暂停就看它。
  Duration maxGap = Duration.zero;

  /// 保活是否真的起来了（前台服务 + 唤醒锁）。
  bool keeping = false;

  DateTime? startedAt;
  DateTime? finishedAt;

  Timer? _timer;
  bool _disposed = false;

  /// 平台是否提供保活能力。Windows 上这个自检没有意义，界面据此隐藏。
  bool get supported => _keeper.supported;

  /// 心跳是否连续：最长间隔没超过两个步长，说明定时器没被系统拖过。
  bool get continuous => phase == ProbePhase.done && ticks > 0 && maxGap <= step * 2;

  Duration get elapsed {
    final DateTime? s = startedAt;
    if (s == null) return Duration.zero;
    return (finishedAt ?? _now()).difference(s);
  }

  /// 给界面直接显示的一句话结论。
  String get verdict {
    if (phase != ProbePhase.done) return '';
    if (ticks == 0) return '没有收到任何心跳：定时器完全停住了';
    if (continuous) {
      return '$ticks 次心跳，最长间隔 ${maxGap.inSeconds} 秒';
    }
    return '最长间隔 ${maxGap.inSeconds} 秒，超过 ${step.inSeconds * 2} 秒说明计时被系统押后过';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 只写调试日志，不进界面。熄屏出问题时用户拿不到任何现场，
  /// 而 adb 一断 logcat 也看不到了——所以这些行留在设备缓冲区里，回来再捞。
  void _trace(String message) {
    if (kDebugMode) debugPrint('[probe] $message');
  }

  Future<void> start() async {
    if (phase == ProbePhase.running || _disposed) return;
    ticks = 0;
    expectedTicks = 0;
    maxGap = Duration.zero;
    startedAt = _now();
    finishedAt = null;
    phase = ProbePhase.running;
    _notify();

    // 和真实执行一样：先要通知权限、再起保活、最后才开始计时，顺序错了就测不出问题。
    // 没有通知权限也能保活（只是通知不可见），所以这里不看返回值。
    await _keeper.ensureNotificationPermission();
    if (_disposed) return;
    keeping = _keeper.supported && await _keeper.begin(title: '保活自检：计时中', body: '第 0 次心跳');
    if (_disposed) return;
    _trace('begin keeping=$keeping');
    _notify();

    _timer?.cancel();
    _lastTickAt = startedAt;
    _timer = Timer.periodic(step, (_) => _onTick());
  }

  DateTime? _lastTickAt;

  void _onTick() {
    final DateTime now = _now();
    final DateTime? last = _lastTickAt;
    Duration gap = Duration.zero;
    if (last != null) {
      gap = now.difference(last);
      if (gap > maxGap) maxGap = gap;
    }
    _lastTickAt = now;
    ticks++;

    final DateTime? s = startedAt;
    if (s == null) return;
    final int seconds = now.difference(s).inSeconds;
    expectedTicks = seconds ~/ step.inSeconds;
    // 逐次记墙钟：事后在 logcat 里能看出表是在哪一段停的，而不是只有个结论。
    _trace('tick $ticks elapsed=${seconds}s gap=${gap.inSeconds}s max=${maxGap.inSeconds}s');

    if (seconds >= total.inSeconds) {
      _finish();
      return;
    }

    if (keeping) {
      // 通知上也能看到心跳在走，熄屏时不必开屏就知道没断。
      unawaited(_keeper.update(
        title: '保活自检：计时中',
        body: '第 $ticks 次心跳 · 最长间隔 ${maxGap.inSeconds}s',
      ));
    }
    _notify();
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    finishedAt = _now();
    phase = ProbePhase.done;
    _trace('finish ticks=$ticks elapsed=${elapsed.inSeconds}s max=${maxGap.inSeconds}s');
    unawaited(_stopKeeping());
    _notify();
  }

  /// 用户中途放弃：一样要把服务撤掉，别留一条常驻通知。
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    phase = ProbePhase.idle;
    startedAt = null;
    finishedAt = null;
    ticks = 0;
    expectedTicks = 0;
    maxGap = Duration.zero;
    await _stopKeeping();
    _notify();
  }

  Future<void> _stopKeeping() async {
    if (!keeping) return;
    keeping = false;
    await _keeper.end();
  }

  /// 仅供测试与视觉取证：摆出一个确定的状态，不启动计时器。
  void seedForPreview({
    required ProbePhase phase,
    int ticks = 0,
    Duration maxGap = Duration.zero,
    Duration elapsed = Duration.zero,
    bool keeping = false,
  }) {
    _timer?.cancel();
    _timer = null;
    this.phase = phase;
    this.ticks = ticks;
    this.maxGap = maxGap;
    this.keeping = keeping;
    startedAt = _now().subtract(elapsed);
    finishedAt = phase == ProbePhase.done ? _now() : null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_stopKeeping());
    super.dispose();
  }
}
