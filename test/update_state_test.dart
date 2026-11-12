import 'dart:io';

import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/core/update/app_release.dart';
import 'package:auto_chaoxing/core/version.dart';
import 'package:auto_chaoxing/state/update_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_update.dart';

void main() {
  DateTime? lastCheck;

  UpdateThrottle throttle() => UpdateThrottle(
        read: () async => lastCheck,
        write: (DateTime t) async => lastCheck = t,
      );

  UpdateState stateWith(
    FakeUpdateChecker checker, {
    FakeInstaller? installer,
    String version = '0.3.3',
  }) {
    lastCheck = null;
    return UpdateState(
      checker: checker,
      installer: installer ?? FakeInstaller(),
      throttle: throttle(),
      currentVersion: version,
      quitApp: () async {},
    );
  }

  group('检查更新', () {
    test('远端版本更高时进入 available', () async {
      final UpdateState s = stateWith(FakeUpdateChecker(release: fakeRelease('v0.4.0')));
      await s.checkForUpdates(force: true);
      expect(s.phase, UpdatePhase.available);
      expect(s.hasUpdate, isTrue);
      expect(s.latest?.version, '0.4.0');
      expect(s.message, contains('0.4.0'));
    });

    test('同版本号视为已最新（含 v 前缀差异）', () async {
      final UpdateState s = stateWith(FakeUpdateChecker(release: fakeRelease('v0.3.3')));
      await s.checkForUpdates(force: true);
      expect(s.phase, UpdatePhase.upToDate);
      expect(s.hasUpdate, isFalse);
    });

    test('远端更低时不提示更新', () async {
      final UpdateState s = stateWith(FakeUpdateChecker(release: fakeRelease('v0.3.0')));
      await s.checkForUpdates(force: true);
      expect(s.phase, UpdatePhase.upToDate);
    });

    test('仓库还没有发布版本时给出说明而不是报错', () async {
      final UpdateState s = stateWith(FakeUpdateChecker(noRelease: true));
      await s.checkForUpdates(force: true);
      expect(s.phase, UpdatePhase.upToDate);
      expect(s.message, contains('还没有发布版本'));
    });

    test('请求失败时进入 failed 并带上原因', () async {
      final UpdateState s = stateWith(
        FakeUpdateChecker(error: const Err<AppRelease?>('network', '连不上 GitHub')),
      );
      await s.checkForUpdates(force: true);
      expect(s.phase, UpdatePhase.failed);
      expect(s.message, '连不上 GitHub');
    });

    test('5 分钟内重复调用只请求一次，手动检查不受限', () async {
      final FakeUpdateChecker checker = FakeUpdateChecker(release: fakeRelease('v0.4.0'));
      final UpdateState s = stateWith(checker);

      await s.checkForUpdates();
      await s.checkForUpdates();
      expect(checker.calls, 1, reason: '窗口内第二次应被节流挡掉');

      await s.checkForUpdates(force: true);
      expect(checker.calls, 2, reason: '手动检查必须真的去查');
    });
  });

  group('下载与安装', () {
    test('成功后交给安装器并进入 ready', () async {
      final FakeInstaller installer = FakeInstaller();
      final UpdateState s = stateWith(
        FakeUpdateChecker(release: fakeRelease('v0.4.0')),
        installer: installer,
      );
      await s.checkForUpdates(force: true);
      await s.downloadAndInstall();

      expect(s.phase, UpdatePhase.ready);
      expect(installer.downloads, 1);
      expect(installer.installedPath, '/tmp/update.apk');
      expect(s.progress, 1.0);
    });

    test('没有安装权限时先引导授权，不下载', () async {
      final FakeInstaller installer = FakeInstaller(canInstallValue: false);
      final UpdateState s = stateWith(
        FakeUpdateChecker(release: fakeRelease('v0.4.0')),
        installer: installer,
      );
      await s.checkForUpdates(force: true);
      await s.downloadAndInstall();

      expect(installer.permissionOpened, isTrue);
      expect(installer.downloads, 0);
      expect(s.phase, UpdatePhase.available, reason: '授权回来后按钮还在，不必重查');
      expect(s.message, contains('允许'));
    });

    test('下载失败时进入 failed 并保留原因', () async {
      final UpdateState s = stateWith(
        FakeUpdateChecker(release: fakeRelease('v0.4.0')),
        installer: FakeInstaller(
          downloadError: const Err<String>('download', '下载超时，请重试'),
        ),
      );
      await s.checkForUpdates(force: true);
      await s.downloadAndInstall();
      expect(s.phase, UpdatePhase.failed);
      expect(s.message, '下载超时，请重试');
    });

    test('版本里没有当前平台的资产时明确说明', () async {
      final UpdateState s = stateWith(
        FakeUpdateChecker(
          release: fakeRelease('v0.4.0', assets: const <ReleaseAsset>[
            ReleaseAsset(name: 'source-code.tar.gz', url: 'https://e/s', size: 10),
          ]),
        ),
      );
      await s.checkForUpdates(force: true);
      await s.downloadAndInstall();
      expect(s.phase, UpdatePhase.failed);
      expect(s.message, contains('没有提供'));
    });
  });

  group('版本号常量', () {
    test('lib 里的版本号与 pubspec.yaml 一致', () {
      // 二者不同步时，检查更新会误判「已是最新」，且很难在界面上发现。
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final RegExpMatch? m = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(pubspec);
      expect(m, isNotNull, reason: 'pubspec.yaml 里应该有 version: x.y.z');
      expect(kAppVersion, m!.group(1));
    });

    test('展示用的版本号带 v', () {
      expect(kAppVersionLabel, 'v$kAppVersion');
    });
  });
}
