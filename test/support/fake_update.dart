// 更新相关测试用的替身：不发网络请求、不碰原生通道。
import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/core/update/app_release.dart';
import 'package:auto_chaoxing/core/update/update_checker.dart';
import 'package:auto_chaoxing/platform/update_installer.dart';

/// 直接返回预设结果，并记录被调了几次（用来验证 5 分钟节流）。
class FakeUpdateChecker extends UpdateChecker {
  FakeUpdateChecker({this.release, this.error, this.noRelease = false});

  AppRelease? release;
  Err<AppRelease?>? error;

  /// true 表示仓库还没有发布版本（Ok(null)）。
  bool noRelease;

  int calls = 0;

  @override
  Future<Result<AppRelease?>> fetchLatest() async {
    calls++;
    if (error != null) return error!;
    if (noRelease) return const Ok<AppRelease?>(null);
    return Ok<AppRelease?>(release);
  }
}

class FakeInstaller implements UpdateInstaller {
  FakeInstaller({
    this.platform = UpdatePlatform.android,
    this.canInstallValue = true,
    this.downloadError,
    this.installError,
  });

  @override
  final UpdatePlatform platform;

  bool canInstallValue;
  Err<String>? downloadError;
  Err<InstallResult>? installError;

  bool permissionOpened = false;
  int downloads = 0;
  String? installedPath;

  @override
  Future<bool> canInstall() async => canInstallValue;

  @override
  Future<void> openInstallPermission() async => permissionOpened = true;

  @override
  Future<Result<String>> download(
    ReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
    dynamic cancelToken,
  }) async {
    downloads++;
    if (downloadError != null) return downloadError!;
    onProgress?.call(50, 100);
    onProgress?.call(100, 100);
    return const Ok<String>('/tmp/update.apk');
  }

  @override
  Future<Result<InstallResult>> install(String path) async {
    installedPath = path;
    if (installError != null) return installError!;
    return const Ok<InstallResult>(InstallResult(InstallMode.automated, '已打开安装界面'));
  }
}

AppRelease fakeRelease(String tag, {List<ReleaseAsset>? assets}) => AppRelease(
      tag: tag,
      title: tag,
      notes: '测试说明',
      publishedAt: null,
      assets: assets ??
          const <ReleaseAsset>[
            ReleaseAsset(name: 'auto-chaoxing-arm64-v8a.apk', url: 'https://e/a.apk', size: 1024),
            ReleaseAsset(name: 'auto-chaoxing-setup.exe', url: 'https://e/s.exe', size: 1024),
          ],
    );
