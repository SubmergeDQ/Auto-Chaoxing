import 'package:auto_chaoxing/core/update/app_release.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('版本比较', () {
    test('逐段按数字比，0.3.10 大于 0.3.9', () {
      expect(compareVersions('0.3.10', '0.3.9'), greaterThan(0));
      expect(compareVersions('0.3.9', '0.3.10'), lessThan(0));
    });

    test('段数不同时短的补 0', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.1', '1.2'), greaterThan(0));
    });

    test('允许带 v 前缀', () {
      expect(compareVersions('v0.4.0', '0.4.0'), 0);
      expect(compareVersions('V0.4.0', '0.3.9'), greaterThan(0));
    });

    test('预发布后缀取数字前缀，不抛异常', () {
      expect(compareVersions('1.0.0-beta', '1.0.0'), 0);
      expect(compareVersions('1.0.1-beta', '1.0.0'), greaterThan(0));
    });

    test('normalizeVersion 只摘掉开头一个 v', () {
      expect(normalizeVersion('v0.3.3'), '0.3.3');
      expect(normalizeVersion('version1'), 'ersion1');
      expect(normalizeVersion('  v1.2  '), '1.2');
    });
  });

  group('按平台挑资产', () {
    const List<ReleaseAsset> assets = <ReleaseAsset>[
      ReleaseAsset(name: 'auto-chaoxing-arm64-v8a.apk', url: 'u1', size: 30 * 1024 * 1024),
      ReleaseAsset(name: 'auto-chaoxing-universal.apk', url: 'u2', size: 40 * 1024 * 1024),
      ReleaseAsset(name: 'auto-chaoxing-setup-0.4.0.exe', url: 'u3', size: 50 * 1024 * 1024),
      ReleaseAsset(name: 'auto-chaoxing-windows-x64.zip', url: 'u4', size: 45 * 1024 * 1024),
      ReleaseAsset(name: 'source-code.tar.gz', url: 'u5', size: 1024),
    ];

    AppRelease release(List<ReleaseAsset> a) => AppRelease(
          tag: 'v0.4.0',
          title: '0.4.0',
          notes: '',
          publishedAt: null,
          assets: a,
        );

    test('Android 优先 arm64 的 apk', () {
      final ReleaseAsset? a = release(assets).assetFor(UpdatePlatform.android);
      expect(a?.name, 'auto-chaoxing-arm64-v8a.apk');
    });

    test('Windows 优先 setup exe', () {
      final ReleaseAsset? a = release(assets).assetFor(UpdatePlatform.windows);
      expect(a?.name, 'auto-chaoxing-setup-0.4.0.exe');
    });

    test('没有安装器时 Windows 退回 windows 的 zip', () {
      final ReleaseAsset? a = release(<ReleaseAsset>[
        const ReleaseAsset(name: 'auto-chaoxing-windows-x64.zip', url: 'u4', size: 1),
        const ReleaseAsset(name: 'docs.zip', url: 'u6', size: 1),
      ]).assetFor(UpdatePlatform.windows);
      expect(a?.name, 'auto-chaoxing-windows-x64.zip');
    });

    test('只有源码包时挑不到资产', () {
      final ReleaseAsset? a = release(<ReleaseAsset>[
        const ReleaseAsset(name: 'source-code.tar.gz', url: 'u5', size: 1),
      ]).assetFor(UpdatePlatform.windows);
      expect(a, isNull);
    });

    test('sizeLabel 按量级取舍', () {
      expect(const ReleaseAsset(name: 'a.apk', url: 'u', size: 0).sizeLabel, '');
      expect(const ReleaseAsset(name: 'a.apk', url: 'u', size: 2 * 1024 * 1024).sizeLabel, '2.00 MB');
      expect(
        const ReleaseAsset(name: 'a.apk', url: 'u', size: 30 * 1024 * 1024).sizeLabel,
        '30.0 MB',
      );
    });
  });

  group('发布解析', () {
    test('从 GitHub release JSON 里取出 tag、说明与资产', () {
      final AppRelease r = AppRelease.fromJson(<String, dynamic>{
        'tag_name': 'v0.4.1',
        'name': '0.4.1 修登录',
        'body': '- 修复 xx',
        'published_at': '2026-11-12T15:00:00Z',
        'assets': <dynamic>[
          <String, dynamic>{
            'name': 'auto-chaoxing-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/a.apk',
            'size': 31457280,
          },
          <String, dynamic>{'name': 'no-url.apk'},
        ],
      });
      expect(r.version, '0.4.1');
      expect(r.title, '0.4.1 修登录');
      expect(r.notes, contains('修复'));
      expect(r.publishedAt, isNotNull);
      // 没有下载地址的资产要丢掉，否则后面下载会拿到空串。
      expect(r.assets.length, 1);
    });
  });

  group('5 分钟节流', () {
    DateTime? stored;

    UpdateThrottle throttle() => UpdateThrottle(
          read: () async => stored,
          write: (DateTime t) async => stored = t,
        );

    test('没查过就要查', () async {
      expect(await throttle().shouldCheck(DateTime(2026, 11, 12, 10, 0)), isTrue);
    });

    test('4 分钟内不重复查，5 分钟后才查', () async {
      final DateTime now = DateTime(2026, 11, 12, 10, 0);
      final UpdateThrottle t = throttle();
      await t.markChecked(now);
      expect(await t.shouldCheck(now.add(const Duration(minutes: 4))), isFalse);
      expect(await t.shouldCheck(now.add(const Duration(minutes: 5))), isTrue);
    });

    test('用户手动检查不受窗口限制', () async {
      final DateTime now = DateTime(2026, 11, 12, 10, 0);
      final UpdateThrottle t = throttle();
      await t.markChecked(now);
      expect(
        await t.shouldCheck(now.add(const Duration(seconds: 10)), force: true),
        isTrue,
      );
    });
  });
}
