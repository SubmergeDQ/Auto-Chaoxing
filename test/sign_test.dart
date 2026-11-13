import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/core/sign_rules.dart';
import 'package:auto_chaoxing/state/sign_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';
import 'support/fake_run_keeper.dart';

void main() {
  group('签到判定规则', () {
    test('预签到 HTML：已签 / 人脸 / 验证码 / 已结束 都能认出来', () {
      expect(judgePreSign('<div>已经签到</div>')?.outcome, SignOutcome.alreadySigned);
      expect(judgePreSign('<div>请完成人脸识别</div>')?.outcome, SignOutcome.needFace);
      expect(judgePreSign('<div>请输入验证码</div>')?.outcome, SignOutcome.needValidate);
      expect(judgePreSign('<div>签到已结束</div>')?.outcome, SignOutcome.expired);
      // 可签：返回 null，继续提交。
      expect(judgePreSign('<html><script>var validate = 1;</script></html>'), isNull);
    });

    test('提交回执：success 成功，success2 视为已结束', () {
      expect(judgeSignResponse('success').outcome, SignOutcome.success);
      expect(judgeSignResponse('success2').outcome, SignOutcome.expired);
      expect(judgeSignResponse('已经签到').outcome, SignOutcome.alreadySigned);
      expect(judgeSignResponse('validate').outcome, SignOutcome.needValidate);
      expect(judgeSignResponse('距离签到地点太远').outcome, SignOutcome.needLocation);
      expect(judgeSignResponse('error').outcome, SignOutcome.error);
    });

    test('时间解析同时支持秒级与毫秒级时间戳', () {
      final DateTime? seconds = parseChaoxingTime(1700000000);
      final DateTime? millis = parseChaoxingTime(1700000000000);
      expect(seconds, isNotNull);
      expect(millis, isNotNull);
      expect(seconds!.millisecondsSinceEpoch, millis!.millisecondsSinceEpoch);
      expect(parseChaoxingTime('2026-11-13 10:30:00')?.hour, 10);
      expect(parseChaoxingTime(''), isNull);
      expect(parseChaoxingTime(null), isNull);
    });

    test('活动可签窗口按起止时间判断，缺时间不当作可签', () {
      final DateTime now = DateTime(2026, 11, 13, 10, 0);
      final SignActivity open = SignActivity(
        activeId: '1',
        name: '签到',
        type: 2,
        status: 1,
        startAt: now.subtract(const Duration(minutes: 1)),
        endAt: now.add(const Duration(minutes: 10)),
      );
      expect(open.isOpenAt(now), isTrue);
      expect(open.isExpiredAt(now), isFalse);

      final SignActivity expired = SignActivity(
        activeId: '2',
        name: '签到',
        type: 2,
        status: 2,
        startAt: now.subtract(const Duration(minutes: 30)),
        endAt: now.subtract(const Duration(minutes: 1)),
      );
      expect(expired.isOpenAt(now), isFalse);
      expect(expired.isExpiredAt(now), isTrue);

      const SignActivity unknown = SignActivity(
        activeId: '3',
        name: '签到',
        type: 2,
        status: 1,
      );
      expect(unknown.isOpenAt(now), isFalse);
    });
  });

  group('SignController', () {
    SignController controllerWith(FakeChaoxingApi api) {
      api.profile = api.demoProfile;
      return SignController(api: api, onChanged: () {});
    }

    test('打开课程后加载活动列表', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(
        signActivities: <SignActivity>[
          SignActivity(
            activeId: 'a1',
            name: '第 3 次课签到',
            type: 2,
            status: 1,
            startAt: DateTime.now().subtract(const Duration(minutes: 5)),
            endAt: DateTime.now().add(const Duration(minutes: 10)),
          ),
        ],
      );
      final SignController controller = controllerWith(api);

      await controller.open(kDemoCourses.first);

      expect(controller.loading, isFalse);
      expect(controller.activities, hasLength(1));
      expect(controller.activities.first.name, '第 3 次课签到');

      controller.dispose();
    });

    test('签到成功后标记已签，同一活动不再提交', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(
        signActivities: <SignActivity>[
          const SignActivity(activeId: 'a1', name: '签到', type: 2, status: 1),
        ],
      );
      final SignController controller = controllerWith(api);
      await controller.open(kDemoCourses.first);
      final SignActivity activity = controller.activities.first;

      final SignAttempt? first = await controller.signIn(activity);
      final SignAttempt? second = await controller.signIn(activity);

      expect(first?.outcome, SignOutcome.success);
      expect(second?.outcome, SignOutcome.alreadySigned);
      expect(controller.wasSigned(activity), isTrue);
      expect(api.signCalls, 1, reason: '第二次是本地拦截，不该再发请求');
      expect(controller.notice, contains('已经签过'));

      controller.dispose();
    });

    test('需要人脸时如实提示，不标记为已签', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(
        signActivities: <SignActivity>[
          const SignActivity(activeId: 'a1', name: '签到', type: 2, status: 1),
        ],
      )..signAttempt = const SignAttempt(
          SignOutcome.needFace,
          message: '需要人脸识别，请在手机上完成',
        );
      final SignController controller = controllerWith(api);
      await controller.open(kDemoCourses.first);

      final SignAttempt? attempt = await controller.signIn(controller.activities.first);

      expect(attempt?.outcome, SignOutcome.needFace);
      expect(controller.wasSigned(controller.activities.first), isFalse);
      expect(controller.notice, contains('人脸'));

      controller.dispose();
    });

    test('活动列表读取失败时保留错误文案', () async {
      final FakeChaoxingApi api = FakeChaoxingApi()
        ..signActivitiesError = '连接超时';
      final SignController controller = controllerWith(api);

      await controller.open(kDemoCourses.first);

      expect(controller.error, '连接超时');
      expect(controller.activities, isEmpty);

      controller.dispose();
    });
  });

  group('签到后台监听', () {
    SignActivity openActivity() => SignActivity(
          activeId: 'a1',
          name: '第 3 次课签到',
          type: 2,
          status: 1,
          startAt: DateTime.now().subtract(const Duration(minutes: 2)),
          endAt: DateTime.now().add(const Duration(minutes: 30)),
        );

    test('监听开启后自动签进行中的活动，并刷新通知', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(
        signActivities: <SignActivity>[openActivity()],
      )..profile = apiDefaultProfile();
      final RunKeeperStub keeper = RunKeeperStub();
      final SignController controller = SignController(
        api: api,
        onChanged: () {},
        keeper: keeper,
        pollInterval: const Duration(milliseconds: 20),
      );

      await controller.open(kDemoCourses.first);
      expect(await controller.startWatching(), isTrue);
      expect(keeper.beginCalls, 1);
      expect(keeper.beginTitle, contains('签到监听'));

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(api.signedActiveIds, <String>['a1']);
      expect(keeper.notices.any((String s) => s.contains('签到成功')), isTrue);

      controller.stopWatching();
      expect(keeper.endCalls, 1);
      controller.dispose();
    });

    test('需要人脸的自动签到只尝试一次，之后停在通知栏提醒', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(
        signActivities: <SignActivity>[openActivity()],
      )
        ..profile = apiDefaultProfile()
        ..signAttempt = const SignAttempt(
          SignOutcome.needFace,
          message: '需要人脸识别，请在手机上完成',
        );
      final RunKeeperStub keeper = RunKeeperStub();
      final SignController controller = SignController(
        api: api,
        onChanged: () {},
        keeper: keeper,
        pollInterval: const Duration(milliseconds: 20),
      );

      await controller.open(kDemoCourses.first);
      await controller.startWatching();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(api.signCalls, 1, reason: '同一个人工活动不该反复自动重试');
      expect(keeper.notices.any((String s) => s.contains('人脸')), isTrue);
      expect(controller.wasSigned(controller.activities.first), isFalse);

      controller.stopWatching();
      controller.dispose();
    });

    test('章节执行中不允许开启监听，避免争用同一个前台服务', () async {
      final FakeChaoxingApi api = FakeChaoxingApi()
        ..profile = apiDefaultProfile();
      final RunKeeperStub keeper = RunKeeperStub();
      final SignController controller = SignController(
        api: api,
        onChanged: () {},
        keeper: keeper,
        isRunBusy: () => true,
      );

      await controller.open(kDemoCourses.first);
      expect(await controller.startWatching(), isFalse);
      expect(keeper.beginCalls, 0);
      expect(controller.notice, contains('结束后'));

      controller.dispose();
    });
  });
}

Profile apiDefaultProfile() => const Profile(uid: '10086', name: '林知远', fid: '666');
