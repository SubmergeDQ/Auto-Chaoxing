import 'dart:io';

import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/core/task_runner.dart';
import 'package:auto_chaoxing/core/update/app_release.dart';
import 'package:auto_chaoxing/platform/keep_alive_settings.dart';
import 'package:auto_chaoxing/platform/platform_services.dart';
import 'package:auto_chaoxing/platform/session_store.dart';
import 'package:auto_chaoxing/platform/window_shell.dart';
import 'package:auto_chaoxing/state/app_state.dart';
import 'package:auto_chaoxing/state/update_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';
import 'support/fake_update.dart';

UpdateState _noUpdate() => UpdateState(
      checker: FakeUpdateChecker(noRelease: true),
      installer: FakeInstaller(),
      throttle: UpdateThrottle(
        read: () async => DateTime.now(),
        write: (DateTime _) async {},
      ),
      currentVersion: '0.3.9',
      quitApp: () async {},
    );

AppState _stateWith(FakeChaoxingApi api, SessionJar store) => AppState(
      api: api,
      session: store,
      sleep: (Duration _) async {},
      runKeeper: const NoopRunKeeper(),
      keepAliveSettings: const NoopKeepAliveSettings(),
      windowShell: const NoopWindowShell(),
      update: _noUpdate(),
    );

const Profile _profileA = Profile(uid: '10086', name: '林知远', fid: '666', school: '示例大学');
const Profile _profileB = Profile(uid: '20001', name: '周敏', fid: '666', school: '另一所大学');

void main() {
  group('多账号隔离与切换', () {
    late Directory root;
    late SessionJar store;
    late FakeChaoxingApi api;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('acx_multi_account');
      store = await SessionJar.open(overrideDir: root.path);
      api = FakeChaoxingApi()
        ..profilesByUid['10086'] = _profileA
        ..profilesByUid['20001'] = _profileB;
    });

    tearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {
        // 忽略占用。
      }
    });

    Future<AppState> signInBoth() async {
      final AppState state = _stateWith(api, store);
      await state.signIn('13800000000', 'pw-a');
      api.loginProfile = _profileB;
      await state.signIn('13900000000', 'pw-b');
      return state;
    }

    test('两个账号各有独立会话，列表按最近使用排序', () async {
      final AppState state = await signInBoth();

      expect(state.activeUid, '20001');
      expect(state.accounts, hasLength(2));
      expect(state.accounts.first.uid, '20001');
      expect(state.accounts[1].uid, '10086');
      expect(await store.hasCookies('10086'), isTrue);
      expect(await store.hasCookies('20001'), isTrue);
    });

    test('切换账号拿到的是那个账号的资料，并把它排到最前', () async {
      final AppState state = await signInBoth();

      final String? error = await state.switchAccount('10086');

      expect(error, isNull);
      expect(state.profile?.uid, '10086');
      expect(state.profile?.name, '林知远');
      expect(state.activeUid, '10086');
      expect(state.accounts.first.uid, '10086');
    });

    test('切换会清空上一个账号的课程与执行状态', () async {
      api.courses = kDemoCourses;
      final AppState state = await signInBoth();
      expect(state.courses, isNotEmpty);

      await state.switchAccount('10086');

      expect(state.selectedCourse, isNull);
      expect(state.chapters, isEmpty);
      expect(state.run.hasRun, isFalse);
    });

    test('断开当前账号保留账号记录，只删它的 cookie', () async {
      final AppState state = await signInBoth();

      await state.signOut();

      expect(state.profile, isNull);
      expect(state.activeUid, isNull);
      expect(state.accounts, hasLength(2), reason: '账号记录要留着，方便快速重登');
      expect(await store.hasCookies('20001'), isFalse);
      expect(await store.hasCookies('10086'), isTrue);
    });

    test('移除账号同时删会话与索引记录', () async {
      final AppState state = await signInBoth();

      await state.removeAccount('20001');

      expect(state.profile, isNull);
      expect(state.accounts, hasLength(1));
      expect(state.accounts.first.uid, '10086');
      expect(await store.hasCookies('20001'), isFalse);
    });

    test('重启后 bootstrap 恢复最近使用的账号', () async {
      await signInBoth();

      // 新的 AppState 模拟重启：同一个存储目录，重新走启动流程。
      final AppState restarted = _stateWith(api, store);
      await restarted.bootstrap();

      expect(restarted.profile?.uid, '20001');
      expect(restarted.activeUid, '20001');
      expect(restarted.coursesState, LoadState.ready);
    });

    test('清除全部账号会删掉索引与所有会话', () async {
      final AppState state = await signInBoth();

      await state.signOutAll();

      expect(state.accounts, isEmpty);
      expect(state.profile, isNull);
      expect(await store.loadAccounts(), isEmpty);
      expect(await store.hasCookies('10086'), isFalse);
      expect(await store.hasCookies('20001'), isFalse);
    });

    test('章节执行中不允许切换或登录新账号', () async {
      final AppState state = await signInBoth();
      state.run.seedForPreview(
        courseName: '高等数学（上）',
        chapterTitle: '第一章 函数与极限',
        progress: const TaskProgress(phase: TaskPhase.running),
      );

      expect(await state.switchAccount('10086'), contains('停止'));
      expect(await state.signIn('13700000000', 'pw'), contains('停止'));
      expect(state.activeUid, '20001', reason: '被拒绝时不该改变当前账号');
    });

    test('登录后拉取头像，断开账号后清空', () async {
      api.avatarData = kTinyPng;
      final AppState state = await signInBoth();
      await Future<void>.delayed(Duration.zero);

      expect(state.avatarBytes, isNotNull);
      expect(api.avatarCalls, greaterThan(0));

      await state.signOut();

      expect(state.avatarBytes, isNull);
    });
  });
}
