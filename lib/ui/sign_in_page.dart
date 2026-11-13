// 签到页：活动列表、手动签到与前台轮询。
//
// 第一版只在前台轮询：签到必须当场完成，而进程被杀后 Dart 计时器不会响。
// 页面把这件事写清楚，避免用户关掉应用后以为还会提醒。
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../platform/keep_alive_settings.dart' show isDesktopWindows;
import '../state/app_state.dart';
import '../state/sign_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.state, required this.course});

  final AppState state;
  final Course course;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  SignController get _sign => widget.state.sign;

  @override
  void initState() {
    super.initState();
    // 首帧之后再拉数据：SignController 会同步 notifyListeners，
    // 在 initState 里直接调用会撞上外层 AnimatedBuilder 正在 build。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_sign.open(widget.course));
      // Windows 没有「手机签到」的语义（定位、课堂场景都在手机上），只保留手动刷新。
      if (!isDesktopWindows) _sign.startPolling();
    });
  }

  @override
  void dispose() {
    _sign.leave();
    super.dispose();
  }

  Future<void> _signIn(SignActivity activity) async {
    final SignAttempt? attempt = await _sign.signIn(activity);
    if (!mounted || attempt == null) return;
    // 结果同时写进页面提示条；这里只给一个短暂的即时反馈。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(attempt.message)),
    );
  }

  Future<void> _toggleWatch(bool on) async {
    if (!on) {
      _sign.stopWatching();
      return;
    }
    final bool started = await _sign.startWatching();
    if (!mounted || started) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_sign.notice ?? '开启监听失败')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('签到')),
      body: AnimatedBuilder(
        animation: widget.state,
        builder: (BuildContext context, Widget? _) => _content(),
      ),
    );
  }

  Widget _content() {
    if (_sign.loading && _sign.activities.isEmpty) {
      return const Center(
        child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    final String? error = _sign.error;
    if (error != null && _sign.activities.isEmpty) {
      return AcxErrorState(
        title: '签到活动读取失败',
        message: error,
        onRetry: () => unawaited(_sign.refresh()),
      );
    }

    final DateTime now = DateTime.now();
    final List<SignActivity> items = _sign.activities;
    return ListView(
      padding: const EdgeInsets.all(AcxSpacing.xl),
      children: <Widget>[
        _Header(
          course: widget.course,
          polling: _sign.polling,
          loading: _sign.loading,
          onRefresh: () => unawaited(_sign.refresh()),
        ),
        const SizedBox(height: AcxSpacing.md),
        _WatchCard(
          sign: _sign,
          onToggle: (bool on) => unawaited(_toggleWatch(on)),
        ),
        if (_sign.notice != null) ...<Widget>[
          const SizedBox(height: AcxSpacing.md),
          _NoticeBanner(text: _sign.notice!),
        ],
        const SizedBox(height: AcxSpacing.lg),
        if (items.isEmpty)
          AcxSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '这门课暂时没有签到活动',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AcxColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AcxSpacing.sm),
                Text(
                  _sign.canWatch
                      ? '开着监听时，老师发起签到后会自动提交；关掉页面不影响监听。'
                      : '这份清单只反映当前课程，老师发起签到后点「刷新」再看。',
                  style: const TextStyle(fontSize: 12, height: 1.6, color: AcxColors.textSecondary),
                ),
              ],
            ),
          )
        else
          ...items.map(
            (SignActivity a) => Padding(
              padding: const EdgeInsets.only(bottom: AcxSpacing.md),
              child: _ActivityCard(
                activity: a,
                signed: _sign.wasSigned(a),
                signing: _sign.signing,
                now: now,
                onSign: () => unawaited(_signIn(a)),
              ),
            ),
          ),
        const SizedBox(height: AcxSpacing.md),
        const Text(
          '定位、人脸与验证码类签到不在自动提交范围内：平台会明确告知，按提示在手机上完成。'
          '同一活动签到成功后不会重复提交；需要人工的活动不会反复自动重试。',
          style: TextStyle(fontSize: 12, height: 1.7, color: AcxColors.textTertiary),
        ),
      ],
    );
  }
}

class _WatchCard extends StatelessWidget {
  const _WatchCard({required this.sign, required this.onToggle});

  final SignController sign;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    if (!sign.canWatch) {
      return const AcxSectionCard(
        padding: EdgeInsets.all(AcxSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline_rounded, size: 16, color: AcxColors.textTertiary),
            SizedBox(width: AcxSpacing.sm),
            Expanded(
              child: Text(
                'Windows 不做后台监听：打开签到页时手动刷新即可，能不能签以平台回执为准。',
                style: TextStyle(fontSize: 12, height: 1.6, color: AcxColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    return AcxSectionCard(
      padding: const EdgeInsets.fromLTRB(
        AcxSpacing.lg, AcxSpacing.sm, AcxSpacing.md, AcxSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.notifications_active_outlined, size: 18, color: AcxColors.brand),
          const SizedBox(width: AcxSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '后台监听签到',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AcxColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sign.runBusy
                      ? '章节执行中先让路，结束后自动恢复检查。'
                      : '每 60 秒检查一次，进行中的签到自动提交；遇人脸 / 验证码会停在通知栏提醒你。',
                  style: const TextStyle(fontSize: 12, height: 1.5, color: AcxColors.textSecondary),
                ),
              ],
            ),
          ),
          Switch(value: sign.watching, onChanged: onToggle),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.course,
    required this.polling,
    required this.loading,
    required this.onRefresh,
  });

  final Course course;
  final bool polling;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                course.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AcxColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                polling ? '每 60 秒刷新一次' : '手动刷新',
                style: const TextStyle(fontSize: 12, color: AcxColors.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(width: AcxSpacing.md),
        OutlinedButton.icon(
          onPressed: loading ? null : onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('刷新'),
        ),
      ],
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AcxSpacing.md),
      decoration: BoxDecoration(
        color: AcxColors.brandSoft,
        borderRadius: BorderRadius.circular(AcxRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded, size: 16, color: AcxColors.brand),
          const SizedBox(width: AcxSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.5, color: AcxColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.activity,
    required this.signed,
    required this.signing,
    required this.now,
    required this.onSign,
  });

  final SignActivity activity;
  final bool signed;
  final bool signing;
  final DateTime now;
  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) {
    final bool open = activity.isOpenAt(now);
    final bool expired = activity.isExpiredAt(now);
    final bool notStarted = !open && !expired && activity.startAt != null;
    // 时间字段没解析出来时不锁死入口：本地判断只是省一次请求，
    // 真正能不能签由平台回执决定。锁死会让「字段格式变了」变成「功能不可用」。
    final bool unknownTime = activity.startAt == null || activity.endAt == null;
    final bool canSign = !signed && !signing && !expired && (open || unknownTime);
    final String label = signed
        ? '已签到'
        : expired
            ? '已结束'
            : open
                ? '进行中'
                : notStarted
                    ? '未开始'
                    : '时间未知';
    final AcxStatus status = signed
        ? AcxStatus.success
        : expired
            ? AcxStatus.idle
            : open
                ? AcxStatus.running
                : notStarted
                    ? AcxStatus.attention
                    : AcxStatus.idle;

    return AcxSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                activity.isSignBack ? Icons.logout_rounded : Icons.how_to_reg_rounded,
                size: 18,
                color: AcxColors.textSecondary,
              ),
              const SizedBox(width: AcxSpacing.sm),
              Expanded(
                child: Text(
                  activity.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AcxColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AcxSpacing.sm),
              AcxStatusBadge(label: label, status: status),
            ],
          ),
          const SizedBox(height: AcxSpacing.sm),
          Text(
            '${activity.isSignBack ? '签退' : '签到'} · ${_windowText(activity)}',
            style: const TextStyle(fontSize: 12, color: AcxColors.textSecondary),
          ),
          const SizedBox(height: AcxSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              // 已签、已结束、未开始都不给按钮：按了也只会拿到一句平台拒绝。
              onPressed: canSign ? onSign : null,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(signed ? '已签到' : signing ? '提交中…' : '签到'),
            ),
          ),
        ],
      ),
    );
  }

  static String _windowText(SignActivity activity) {
    final DateTime? start = activity.startAt;
    final DateTime? end = activity.endAt;
    if (start == null && end == null) return '时间未知';
    if (start == null) return '截止 ${_time(end!)}';
    if (end == null) return '${_time(start)} 开始';
    return '${_time(start)} – ${_time(end)}';
  }

  static String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
