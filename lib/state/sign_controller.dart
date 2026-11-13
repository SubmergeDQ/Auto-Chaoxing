// 签到会话：活动列表、手动签到、前台轮询与后台监听。
//
// 两种轮询：
//   · 页面轮询：打开签到页时刷新列表，离开就停；
//   · 后台监听：用户显式开启，复用 Android 前台服务保活，发现可签活动自动签到。
// 监听与视频执行共用同一个前台服务，同时使用会互相覆盖通知，
// 所以监听在视频执行期间只跳过请求，执行结束后自动恢复。
import 'dart:async';

import '../core/chaoxing_api.dart';
import '../core/models.dart';
import '../platform/platform_services.dart';

class SignController {
  SignController({
    required ChaoxingApi api,
    required void Function() onChanged,
    Future<void> Function(Duration)? sleep,
    RunKeeper keeper = const NoopRunKeeper(),
    bool Function()? isRunBusy,
    Duration pollInterval = const Duration(seconds: 60),
  })  : _api = api,
        _onChanged = onChanged,
        _sleep = sleep,
        _keeper = keeper,
        _isRunBusy = isRunBusy,
        _interval = pollInterval {
    // 通知栏的「停止」对监听同样有效：用户点了就停下，不再自动签到。
    _stopSub = _keeper.stopRequests.listen((void _) {
      if (_watching) stopWatching();
    });
  }

  /// 与协议文档一致的轮询间隔：只在该课程有课时才有意义，60s 足够。
  static const Duration pollInterval = Duration(seconds: 60);

  final ChaoxingApi _api;
  final void Function() _onChanged;
  final Future<void> Function(Duration)? _sleep;
  final RunKeeper _keeper;
  final bool Function()? _isRunBusy;
  final Duration _interval;

  Course? course;
  List<SignActivity> activities = <SignActivity>[];
  bool loading = false;
  bool signing = false;
  String? error;

  /// 最近一次操作的一句话结果（签到成功 / 需要人脸 / 刷新失败原因）。
  String? notice;

  /// 已经签到成功的活动 id。同一活动不再发第二次，平台会判异常。
  final Set<String> _signed = <String>{};

  /// 自动签到遇到人脸 / 验证码 / 定位后放弃的活动：不再自动重试，
  /// 但 UI 仍按「进行中」展示，用户可以自己去手机端完成。
  final Set<String> _manualNeeded = <String>{};

  Timer? _poll;
  StreamSubscription<void>? _stopSub;
  bool _disposed = false;

  /// 监听是否持有前台服务。视频执行会复用同一个服务，
  /// 这个标志只用于「停止监听时该不该撤服务」。
  bool _holdingService = false;

  bool get polling => _poll != null;

  bool get canWatch => _keeper.supported;

  bool _watching = false;

  bool get watching => _watching;

  bool get runBusy => _isRunBusy?.call() ?? false;

  bool wasSigned(SignActivity activity) => _signed.contains(activity.activeId);

  /// 进入课程：记住课程并立即拉一次活动列表。
  Future<void> open(Course value) async {
    if (_disposed) return;
    if (course?.key != value.key) {
      course = value;
      activities = <SignActivity>[];
      error = null;
      notice = null;
      _onChanged();
    }
    await refresh();
  }

  Future<void> refresh() async {
    final Course? current = course;
    if (current == null || _disposed) return;
    loading = true;
    error = null;
    _onChanged();

    final Result<List<SignActivity>> r = await _api.fetchSignActivities(course: current);
    if (_disposed) return;
    loading = false;
    if (r is Err<List<SignActivity>>) {
      error = r.code == 'authExpired' ? '登录已失效，请重新连接账号' : r.message;
    } else {
      activities = (r as Ok<List<SignActivity>>).value;
    }
    _onChanged();
  }

  /// 手动签一次。返回 null 表示当前无法发起（未登录 / 没有课程 / 正在签）。
  Future<SignAttempt?> signIn(SignActivity activity) async {
    final Course? current = course;
    final Profile? me = _api.profile;
    if (current == null || signing || _disposed) return null;

    if (me == null) {
      // 没有账号信息就发不了签到：uid / name / fid 都是协议参数。
      notice = '请先连接账号再签到';
      _onChanged();
      return null;
    }

    if (wasSigned(activity)) {
      notice = '这节课已经签过了';
      _onChanged();
      return const SignAttempt(SignOutcome.alreadySigned, message: '这节课已经签过了');
    }

    signing = true;
    notice = null;
    _onChanged();

    final Result<SignAttempt> r = await _api.signIn(
      course: current,
      activity: activity,
      uid: me.uid,
      name: me.name,
      fid: me.fid,
    );
    if (_disposed) return null;
    signing = false;

    if (r is Err<SignAttempt>) {
      notice = r.code == 'authExpired' ? '登录已失效，请重新连接账号' : r.message;
      _onChanged();
      return null;
    }

    final SignAttempt attempt = (r as Ok<SignAttempt>).value;
    if (attempt.ok) _signed.add(activity.activeId);
    notice = attempt.message;
    // 成功后活动状态在服务端已变，拉一次让界面同步；失败不拉，保留现场。
    if (attempt.outcome == SignOutcome.success) {
      unawaited(_refreshQuietly());
    }
    _onChanged();
    return attempt;
  }

  /// 轮询期间的成功刷新不闪 loading：列表每 60 秒抖一下很像卡了。
  Future<void> _refreshQuietly() async {
    final Course? current = course;
    if (current == null || _disposed) return;
    final Result<List<SignActivity>> r = await _api.fetchSignActivities(course: current);
    if (_disposed || r is! Ok<List<SignActivity>>) return;
    activities = r.value;
    _onChanged();
  }

  /// 开始前台轮询。重复调用只保留一个计时器。
  void startPolling() {
    if (_disposed || _poll != null) return;
    _poll = Timer.periodic(_interval, (Timer _) {
      unawaited(_tick());
    });
    _onChanged();
  }

  Future<void> _tick() async {
    if (_disposed || loading) return;
    // 视频执行期间不抢网络也不抢通知：执行结束后下一轮自动恢复。
    if (_watching && runBusy) return;
    final Future<void> Function(Duration)? delay = _sleep;
    if (delay != null) await delay(Duration.zero);
    await refresh();
    if (_watching) await _autoSignOpen();
  }

  /// 后台监听：起前台服务保活，并在轮询里自动签进行中的活动。
  ///
  /// 返回 false 表示当前开不了（平台不支持 / 执行中 / 正在监听），原因写进 notice。
  Future<bool> startWatching() async {
    if (_disposed || _watching) return false;
    if (!_keeper.supported) {
      notice = '当前平台不支持后台监听';
      _onChanged();
      return false;
    }
    if (course == null) {
      notice = '先选择课程再开启监听';
      _onChanged();
      return false;
    }
    if (runBusy) {
      // 与视频执行共用同一个前台服务，同时开启会互相覆盖通知。
      notice = '正在执行章节，结束后再开启监听';
      _onChanged();
      return false;
    }

    final bool notifyOk = await _keeper.ensureNotificationPermission();
    final bool ok = await _keeper.begin(
      title: '签到监听中：${course!.name}',
      body: '每 60 秒检查一次，发现签到会自动提交',
    );
    if (_disposed) {
      if (ok) unawaited(_keeper.end());
      return false;
    }
    _holdingService = ok;
    _watching = true;
    notice = ok
        ? (notifyOk ? '已开启签到监听' : '已开启监听，但通知栏不可见')
        : '已开启监听，但后台保活没起来：切后台后可能被系统暂停';
    startPolling();
    _onChanged();
    return true;
  }

  /// 停止监听。视频执行中不撤服务：那个服务现在承载的是执行进度。
  void stopWatching() {
    if (!_watching) return;
    _watching = false;
    stopPolling();
    if (_holdingService && !runBusy) unawaited(_keeper.end());
    _holdingService = false;
    notice = '已停止签到监听';
    _onChanged();
  }

  /// 自动签掉当前所有处于时间窗内、还没有签过的活动。
  Future<void> _autoSignOpen() async {
    final DateTime now = DateTime.now();
    for (final SignActivity activity in List<SignActivity>.of(activities)) {
      if (_disposed || !_watching) return;
      if (wasSigned(activity) || _manualNeeded.contains(activity.activeId)) continue;
      if (!activity.isOpenAt(now)) continue;
      final SignAttempt? attempt = await signIn(activity);
      if (attempt == null) continue;
      _notifyWatch(activity, attempt);
    }
  }

  void _notifyWatch(SignActivity activity, SignAttempt attempt) {
    if (!_holdingService) return;
    final String body = attempt.ok
        ? '${activity.name}：${attempt.message}'
        : '${activity.name}：${attempt.message}（已停止自动重试）';
    unawaited(_keeper.update(
      title: attempt.ok ? '已签到：${course?.name ?? ''}' : '需要人工：${course?.name ?? ''}',
      body: body,
    ));
    // 需要人工的活动不再自动重试：平台会给出同样的拒绝，反复请求会被判异常。
    if (!attempt.ok) _manualNeeded.add(activity.activeId);
  }

  void stopPolling() {
    final Timer? timer = _poll;
    if (timer == null) return;
    timer.cancel();
    _poll = null;
    _onChanged();
  }

  /// 离开签到页：没开监听就停轮询；开了监听则继续跑。
  void leave() {
    if (!_watching) stopPolling();
  }

  /// 断开连接时彻底清空，避免上一个账号的活动挂到下一个账号上。
  void reset() {
    _watching = false;
    stopPolling();
    if (_holdingService) unawaited(_keeper.end());
    _holdingService = false;
    course = null;
    activities = <SignActivity>[];
    loading = false;
    signing = false;
    error = null;
    notice = null;
    _signed.clear();
    _manualNeeded.clear();
    _onChanged();
  }

  void dispose() {
    _disposed = true;
    _watching = false;
    _poll?.cancel();
    _poll = null;
    _stopSub?.cancel();
    _stopSub = null;
    if (_holdingService) unawaited(_keeper.end());
    _holdingService = false;
  }
}
