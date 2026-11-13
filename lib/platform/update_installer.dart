// 更新包的下载与安装。平台差异只在这一层。
//
// Android：下到 cache 目录 → FileProvider → 系统安装器（就地覆盖安装）。
// Windows：下到临时目录 → 启动安装器 → 由调用方退出应用，让安装器能覆盖文件。
//
// 为什么 Windows 必须先退出：exe / dll 被当前进程占用时安装器写不进去，
// 表现出来就是「卡在正在复制文件」或者装完还是旧版本。
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';
import '../core/update/app_release.dart';
import '../core/update/update_script.dart';

/// 安装结果。manual 表示只能给用户路径、让他自己来（例如只发布了 zip）。
enum InstallMode { automated, manual }

class InstallResult {
  const InstallResult(this.mode, this.message);

  final InstallMode mode;
  final String message;
}

abstract class UpdateInstaller {
  UpdatePlatform get platform;

  /// 是否需要先授予「安装未知来源应用」。Windows 恒为 true。
  Future<bool> canInstall();

  /// 打开授权页（仅 Android 有意义）。
  Future<void> openInstallPermission();

  /// 返回本地文件路径。onProgress 的 total 为 0 时表示服务器没给长度。
  Future<Result<String>> download(
    ReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  });

  Future<Result<InstallResult>> install(String path);
}

UpdateInstaller createUpdateInstaller() {
  if (defaultTargetPlatform == TargetPlatform.android) return AndroidUpdateInstaller();
  if (defaultTargetPlatform == TargetPlatform.windows) return WindowsUpdateInstaller();
  return const NoopUpdateInstaller();
}

/// 下载到临时目录。两端共用，差别只在下载完成之后做什么。
Future<Result<String>> _downloadToTemp(
  ReleaseAsset asset, {
  void Function(int received, int total)? onProgress,
  CancelToken? cancelToken,
}) async {
  try {
    final Directory dir = await getTemporaryDirectory();
    // 资产名带架构与扩展名，直接沿用便于用户事后在文件管理器里认出来。
    final String safeName = asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final String path = '${dir.path}${Platform.pathSeparator}update_$safeName';
    final File file = File(path);
    if (await file.exists()) await file.delete();
    await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 10),
        headers: <String, dynamic>{'User-Agent': 'Auto-Chaoxing-updater'},
      ),
    ).download(
      asset.url,
      path,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
      // GitHub 的 release 资产会 302 到 objects.githubusercontent.com，必须跟随。
      options: Options(followRedirects: true, maxRedirects: 6),
    );
    if (!await file.exists() || await file.length() == 0) {
      return const Err<String>('download', '下载完成但文件是空的');
    }
    return Ok<String>(path);
  } on DioException catch (e) {
    if (CancelToken.isCancel(e)) {
      return const Err<String>('cancelled', '已取消下载');
    }
    return Err<String>('download', _downloadError(e));
  } on Exception catch (e) {
    return Err<String>('download', '下载失败：$e');
  }
}

String _downloadError(DioException e) {
  return switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout =>
      '下载超时，请重试',
    DioExceptionType.connectionError => '下载中断，请检查网络',
    DioExceptionType.badResponse => '下载失败（HTTP ${e.response?.statusCode}）',
    _ => '下载失败：${e.message ?? e.type.name}',
  };
}

class AndroidUpdateInstaller implements UpdateInstaller {
  static const MethodChannel _channel = MethodChannel('cn.autochaoxing/installer');

  @override
  UpdatePlatform get platform => UpdatePlatform.android;

  @override
  Future<bool> canInstall() async {
    try {
      return (await _channel.invokeMethod<bool>('canInstall')) ?? true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Future<void> openInstallPermission() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on PlatformException {
      // 打不开就算了，用户自己去系统设置里找。
    }
  }

  @override
  Future<Result<String>> download(
    ReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) =>
      _downloadToTemp(asset, onProgress: onProgress, cancelToken: cancelToken);

  @override
  Future<Result<InstallResult>> install(String path) async {
    try {
      final bool ok = (await _channel.invokeMethod<bool>('installApk', <String, dynamic>{
            'path': path,
          })) ??
          false;
      if (!ok) {
        return const Err<InstallResult>('install', '没能拉起系统安装器，请检查安装权限');
      }
      return const Ok<InstallResult>(
        InstallResult(InstallMode.automated, '已打开系统安装界面，按提示完成更新'),
      );
    } on PlatformException catch (e) {
      return Err<InstallResult>('install', '安装失败：${e.message ?? e.code}');
    }
  }
}

class WindowsUpdateInstaller implements UpdateInstaller {
  @override
  UpdatePlatform get platform => UpdatePlatform.windows;

  @override
  Future<bool> canInstall() async => true;

  @override
  Future<void> openInstallPermission() async {}

  @override
  Future<Result<String>> download(
    ReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) =>
      _downloadToTemp(asset, onProgress: onProgress, cancelToken: cancelToken);

  @override
  Future<Result<InstallResult>> install(String path) async {
    if (path.toLowerCase().endsWith('.zip')) return _applyZip(path);
    try {
      await Process.start(path, const <String>[], mode: ProcessStartMode.detached);
      return const Ok<InstallResult>(
        InstallResult(InstallMode.automated, '安装程序已启动，应用将退出以便覆盖文件'),
      );
    } on Exception catch (e) {
      return Err<InstallResult>('install', '没能启动安装程序：$e');
    }
  }

  /// zip 更新：解压到临时目录 → 写覆盖脚本 → 启动脚本 → 由调用方退出应用。
  ///
  /// 三处保护：
  ///   1) 安装目录不可写（例如装在 Program Files）就退回手动，不假装成功；
  ///   2) 解压后先确认包里有主程序，避免把结构不对的包覆盖进去；
  ///   3) 脚本覆盖前备份主 exe，覆盖失败时至少还能启动旧版本。
  Future<Result<InstallResult>> _applyZip(String zipPath) async {
    final String appDir = File(Platform.resolvedExecutable).parent.path;
    final String exeName = Platform.resolvedExecutable.split(Platform.pathSeparator).last;

    if (!await canWriteToDirectory(appDir)) {
      return Ok<InstallResult>(
        InstallResult(
          InstallMode.manual,
          '已下载到 $zipPath；当前安装目录不可写，退出应用后手动解压覆盖',
        ),
      );
    }

    final Directory temp = await getTemporaryDirectory();
    final Directory staging = Directory(
      '${temp.path}${Platform.pathSeparator}acx_update_'
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      await staging.create(recursive: true);
      final ProcessResult r = await Process.run('powershell', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Expand-Archive -LiteralPath '${_psQuote(zipPath)}' "
            "-DestinationPath '${_psQuote(staging.path)}' -Force",
      ]);
      if (r.exitCode != 0) {
        return Err<InstallResult>('install', '解压更新包失败：${r.stderr}');
      }
      if (!File('${staging.path}${Platform.pathSeparator}$exeName').existsSync()) {
        return Err<InstallResult>('install', '更新包结构不对：没有找到 $exeName');
      }

      final File script = File('${temp.path}${Platform.pathSeparator}acx_apply_update.ps1');
      await script.writeAsString(
        buildWindowsApplyScript(
          pid: pid,
          stagingDir: staging.path,
          appDir: appDir,
          exeName: exeName,
        ),
        flush: true,
      );
      await Process.start(
        'powershell',
        <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          script.path,
        ],
        mode: ProcessStartMode.detached,
      );
      return const Ok<InstallResult>(
        InstallResult(InstallMode.automated, '更新包已就绪：应用将退出，随后自动覆盖并重启'),
      );
    } on Exception catch (e) {
      return Err<InstallResult>('install', '准备更新失败：$e');
    }
  }
}

String _psQuote(String value) => value.replaceAll("'", "''");

/// 目录是否可写。安装在 Program Files 时普通用户没有写权限，
/// 这种情况只能走手动解压，不能假装自动更新成功。
Future<bool> canWriteToDirectory(String path) async {
  try {
    final File probe = File('$path${Platform.pathSeparator}.acx_write_probe');
    await probe.writeAsString('probe', flush: true);
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

class NoopUpdateInstaller implements UpdateInstaller {
  const NoopUpdateInstaller();

  @override
  UpdatePlatform get platform => UpdatePlatform.android;

  @override
  Future<bool> canInstall() async => false;

  @override
  Future<void> openInstallPermission() async {}

  @override
  Future<Result<String>> download(
    ReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async =>
      const Err<String>('unsupported', '当前平台不支持应用内更新');

  @override
  Future<Result<InstallResult>> install(String path) async =>
      const Err<InstallResult>('unsupported', '当前平台不支持应用内更新');
}
