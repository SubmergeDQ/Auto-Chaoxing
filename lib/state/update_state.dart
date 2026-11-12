// 检查更新的状态机：节流 → 查 GitHub Release → 比较版本 → 下载 → 安装。
// 不碰 UI，不直接读平台；所有外部能力都从这里注入，便于测试。
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../core/update/app_release.dart';
import '../core/update/update_checker.dart';
import '../core/version.dart';
import '../platform/update_installer.dart';

enum UpdatePhase {
  /// 还没查过，或上次查完太久了。
  idle,

  /// 正在请求 GitHub。
  checking,

  /// 已是最新。
  upToDate,

  /// 有新版本，等用户决定要不要下载。
  available,

  /// 正在下载更新包。
  downloading,

  /// 下载完成并已交给系统安装器（或给出路径让用户手动处理）。
  ready,

  /// 出错了，message 里是给人看的原因。
  failed,
}

class UpdateState extends ChangeNotifier {
  UpdateState({
    UpdateChecker? checker,
    UpdateInstaller? installer,
    UpdateThrottle? throttle,
    this.currentVersion = kAppVersion,
    Future<void> Function()? quitApp,
  })  : checker = checker ?? UpdateChecker(),
        installer = installer ?? createUpdateInstaller(),
        _throttle = throttle ??
            const UpdateThrottle(read: _readLastCheck, write: _writeLastCheck),
        _quitApp = quitApp;

  final UpdateChecker checker;
  final UpdateInstaller installer;
  final UpdateThrottle _throttle;
  final String currentVersion;
  final Future<void> Function()? _quitApp;

  UpdatePhase phase = UpdatePhase.idle;
  String? message;

  /// 远端最新发布，拿不到时为 null（仓库没有发布版本 / 请求失败）。
  AppRelease? latest;

  /// 下载进度 0..1；总长度未知时为 null（UI 改成不确定进度条）。
  double? progress;

  bool _disposed = false;
  CancelToken? _cancel;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel('dispose');
    super.dispose();
  }

  /// 有没有比当前版本更新的发布。
  bool get hasUpdate {
    final AppRelease? r = latest;
    if (r == null) return false;
    return compareVersions(r.version, currentVersion) > 0;
  }

  /// 当前平台能下到的那个资产。null 表示这个 release 没为我们平台准备包。
  ReleaseAsset? get targetAsset => latest?.assetFor(installer.platform);

  UpdatePlatform get platform => installer.platform;

  /// 检查更新。[force] 为 true 表示用户主动点击，无视 5 分钟窗口。
  ///
  /// 自动检查（force=false）失败时不把 UI 切到 failed：用户只是打开了应用，
  /// 不该被一个后台请求的错误打断，message 留给关于页显示即可。
  Future<void> checkForUpdates({bool force = false}) async {
    if (phase == UpdatePhase.checking || phase == UpdatePhase.downloading) return;
    final DateTime now = DateTime.now();
    if (!await _throttle.shouldCheck(now, force: force)) {
      // 窗口内：保留上次结论（可能是 available），不要把它冲掉。
      return;
    }

    phase = UpdatePhase.checking;
    message = null;
    _notify();

    final Result<AppRelease?> r = await checker.fetchLatest();
    await _throttle.markChecked(now);

    switch (r) {
      case Ok<AppRelease?>(value: null):
        latest = null;
        phase = UpdatePhase.upToDate;
        message = '仓库还没有发布版本';
      case Ok<AppRelease?>(value: final AppRelease release):
        latest = release;
        if (compareVersions(release.version, currentVersion) > 0) {
          phase = UpdatePhase.available;
          message = '发现新版本 ${release.version}';
        } else {
          phase = UpdatePhase.upToDate;
          message = '已是最新版本';
        }
      case Err<AppRelease?>():
        latest = null;
        phase = UpdatePhase.failed;
        message = r.message;
    }
    _notify();
  }

  /// 下载并交给安装器。Windows 的 automated 分支会退出应用。
  Future<void> downloadAndInstall() async {
    if (phase == UpdatePhase.downloading) return;
    final ReleaseAsset? asset = targetAsset;
    if (asset == null) {
      phase = UpdatePhase.failed;
      message = '这个版本没有提供适用于当前平台的安装包';
      _notify();
      return;
    }

    if (installer.platform == UpdatePlatform.android && !await installer.canInstall()) {
      // 没授予「安装未知来源」时先把用户送到授权页，回来后按钮还在，不必重新查。
      phase = UpdatePhase.available;
      message = '需要先允许本应用安装应用，请在系统设置里打开后返回重试';
      _notify();
      await installer.openInstallPermission();
      return;
    }

    phase = UpdatePhase.downloading;
    progress = null;
    message = '正在下载 ${asset.name}';
    _notify();

    final CancelToken token = CancelToken();
    _cancel = token;
    final Result<String> dl = await installer.download(
      asset,
      cancelToken: token,
      onProgress: (int received, int total) {
        if (phase != UpdatePhase.downloading) return;
        progress = total > 0 ? (received / total).clamp(0, 1) : null;
        _notify();
      },
    );
    _cancel = null;

    switch (dl) {
      case Err<String>():
        phase = UpdatePhase.failed;
        message = dl.message;
        _notify();
        return;
      case Ok<String>():
        break;
    }

    final Result<InstallResult> inst = await installer.install(dl.value);
    switch (inst) {
      case Ok<InstallResult>(value: final InstallResult out):
        phase = UpdatePhase.ready;
        message = out.message;
        _notify();
        if (out.mode == InstallMode.automated &&
            installer.platform == UpdatePlatform.windows) {
          // 安装器已经起来了：退出，让安装包能覆盖正在运行的 exe / dll。
          await _quitApp?.call();
        }
      case Err<InstallResult>():
        phase = UpdatePhase.failed;
        message = inst.message;
        _notify();
    }
  }

  void cancelDownload() {
    _cancel?.cancel('user');
    if (phase == UpdatePhase.downloading) {
      phase = UpdatePhase.available;
      message = '已取消下载';
      _notify();
    }
  }

  // ------------------------------------------------------- 节流用的时间戳

  static const String _kLastCheck = 'last_update_check_ms';

  static Future<DateTime?> _readLastCheck() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? ms = prefs.getInt(_kLastCheck);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeLastCheck(DateTime t) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastCheck, t.millisecondsSinceEpoch);
    } catch (_) {
      // 记不住就每次都查一次，比永远不查安全。
    }
  }
}

/// 真正退出进程。Windows 上 SystemNavigator.pop 只关掉 Flutter 视图，
/// 进程还活着会占着 exe，安装器就写不进去。
Future<void> quitApplication() async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  exit(0);
}
