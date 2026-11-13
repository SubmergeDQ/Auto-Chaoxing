import 'dart:io';

import 'package:auto_chaoxing/platform/session_store.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('多账号会话存储', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('acx_session_test');
    });

    tearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {
        // 文件被占用时不强删。
      }
    });

    Future<void> writeCookie(CookieJar jar, String uid) async {
      await jar.saveFromResponse(
        Uri.parse('https://chaoxing.com'),
        <Cookie>[Cookie('_uid', uid)..domain = '.chaoxing.com'..path = '/'],
      );
    }

    test('账号索引可以写入并读回', () async {
      final SessionJar store = await SessionJar.open(overrideDir: root.path);
      await store.saveAccounts(<StoredAccount>[
        StoredAccount(
          uid: '10086',
          name: '林知远',
          school: '示例大学',
          username: '13800000000',
          lastUsedAt: DateTime(2026, 11, 13, 10),
        ),
        const StoredAccount(uid: '20001', name: '周敏'),
      ]);

      final List<StoredAccount> loaded = await store.loadAccounts();

      expect(loaded, hasLength(2));
      expect(loaded.first.uid, '10086');
      expect(loaded.first.school, '示例大学');
      expect(loaded.first.username, '13800000000');
      expect(loaded.first.lastUsedAt?.hour, 10);
      expect(loaded[1].name, '周敏');
    });

    test('登录先写临时目录，提交后成为该账号的独立会话', () async {
      final SessionJar store = await SessionJar.open(overrideDir: root.path);

      final CookieJar pending = await store.beginLogin();
      await writeCookie(pending, '10086');
      await store.commitLogin('10086');

      expect(store.isAccountScoped, isTrue);
      expect(await store.hasCookies('10086'), isTrue);

      // 切到另一个账号后再切回来，cookie 还在。
      await store.activate('20001');
      expect(await store.hasCookies('10086'), isTrue);
      final CookieJar back = await store.activate('10086');
      final List<Cookie> cookies =
          await back.loadForRequest(Uri.parse('https://chaoxing.com'));
      expect(cookies.any((Cookie c) => c.name == '_uid' && c.value == '10086'), isTrue);
    });

    test('旧版根目录会话可以迁移到 uid 子目录', () async {
      final SessionJar store = await SessionJar.open(overrideDir: root.path);
      await writeCookie(store.jar, '10086');

      final bool ok = await store.promoteLegacy('10086');

      expect(ok, isTrue);
      expect(store.isAccountScoped, isTrue);
      final List<Cookie> cookies =
          await store.jar.loadForRequest(Uri.parse('https://chaoxing.com'));
      expect(cookies.any((Cookie c) => c.name == '_uid'), isTrue);
      expect(await store.hasCookies('10086'), isTrue);
    });

    test('移除账号只删该账号目录，不清其他账号', () async {
      final SessionJar store = await SessionJar.open(overrideDir: root.path);
      await store.beginLogin();
      await writeCookie(store.jar, '10086');
      await store.commitLogin('10086');
      await store.beginLogin();
      await writeCookie(store.jar, '20001');
      await store.commitLogin('20001');

      await store.purgeAccount('10086');

      expect(await store.hasCookies('10086'), isFalse);
      expect(await store.hasCookies('20001'), isTrue);
    });

    test('清除全部会话会删掉目录与账号索引', () async {
      final SessionJar store = await SessionJar.open(overrideDir: root.path);
      await store.beginLogin();
      await writeCookie(store.jar, '10086');
      await store.commitLogin('10086');
      await store.saveAccounts(
        <StoredAccount>[const StoredAccount(uid: '10086', name: '林知远')],
      );

      await store.purgeAll();

      expect(await store.loadAccounts(), isEmpty);
      expect(await store.hasCookies('10086'), isFalse);
      expect(store.isAccountScoped, isFalse);
    });
  });
}
