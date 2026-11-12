import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/platform/platform_services.dart';
import 'package:auto_chaoxing/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  group('AppState', () {
    test('初始为未登录 / idle', () {
      final AppState state = AppState(
        api: FakeChaoxingApi(),
        runKeeper: const NoopRunKeeper(),
      );
      expect(state.signedIn, isFalse);
      expect(state.coursesState, LoadState.idle);
      expect(state.selectedCourse, isNull);
    });

    test('登录成功后自动拉课程并更新计数', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(courses: kDemoCourses);
      final AppState state = AppState(api: api, runKeeper: const NoopRunKeeper());

      final String? error = await state.signIn('13800000000', 'secret');

      expect(error, isNull);
      expect(state.signedIn, isTrue);
      expect(state.profile?.uid, '10086');
      expect(state.coursesState, LoadState.ready);
      expect(state.courses.length, kDemoCourses.length);
      expect(state.activeCourses, 3);
      expect(state.archivedCourses, 1);
      expect(api.coursesCalls, 1);
    });

    test('登录失败返回可读文案，且不触发课程请求', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(loginError: '密码错误');
      final AppState state = AppState(api: api, runKeeper: const NoopRunKeeper());

      final String? error = await state.signIn('13800000000', 'wrong');

      expect(error, '密码错误');
      expect(state.signedIn, isFalse);
      expect(api.coursesCalls, 0);
    });

    test('needsAttention 单独提示人工处理', () async {
      final AppState state = AppState(
        api: FakeChaoxingApi(
          loginError: '需要验证码',
          loginErrorCode: 'needsAttention',
        ),
        runKeeper: const NoopRunKeeper(),
      );

      final String? error = await state.signIn('13800000000', 'secret');

      expect(error, contains('需要人工验证'));
      expect(state.signedIn, isFalse);
    });

    test('课程读取失败进入 error 且保留重试能力', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(coursesError: '连接超时');
      final AppState state = AppState(api: api, runKeeper: const NoopRunKeeper());
      await state.signIn('13800000000', 'secret');
      expect(state.coursesState, LoadState.error);
      expect(state.coursesError, '连接超时');

      api.coursesError = null;
      api.courses = kDemoCourses;
      await state.loadCourses();

      expect(state.coursesState, LoadState.ready);
      expect(state.courses.length, kDemoCourses.length);
    });

    test('选课程后加载章节，展开按需加载任务点且不重复请求', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(
        courses: kDemoCourses,
        chapters: kDemoChapters,
        points: kDemoPoints,
      );
      final AppState state = AppState(api: api, runKeeper: const NoopRunKeeper());
      await state.signIn('13800000000', 'secret');

      await state.selectCourse(kDemoCourses.first);

      expect(state.selectedCourse?.name, '高等数学（上）');
      expect(state.chaptersState, LoadState.ready);
      expect(state.chapters.length, kDemoChapters.length);

      await state.loadPoints(kDemoChapters.first);
      expect(state.pointsFor('510001')?.length, kDemoPoints.length);
      expect(api.cardsCalls, 1);

      await state.loadPoints(kDemoChapters.first);
      expect(api.cardsCalls, 1, reason: '同一章节不应重复请求');
    });

    test('章节未开放映射为可读提示，不当作解析失败', () async {
      final AppState state = AppState(
        api: FakeChaoxingApi(chapters: kDemoChapters, cardsErrorCode: 'locked'),
        runKeeper: const NoopRunKeeper(),
      );
      state.profile = const Profile(uid: '10086', name: '林知远', fid: '666');
      await state.selectCourse(kDemoCourses.first);

      await state.loadPoints(kDemoChapters.first);

      expect(state.errorFor('510001'), contains('章节未开放'));
      expect(state.pointsFor('510001'), isEmpty);
    });

    test('断开连接清空账号、课程与章节缓存', () async {
      final AppState state = AppState(
        api: FakeChaoxingApi(courses: kDemoCourses, chapters: kDemoChapters),
        runKeeper: const NoopRunKeeper(),
      );
      await state.signIn('13800000000', 'secret');
      await state.selectCourse(kDemoCourses.first);

      state.signOut();

      expect(state.signedIn, isFalse);
      expect(state.courses, isEmpty);
      expect(state.selectedCourse, isNull);
      expect(state.chapters, isEmpty);
    });
  });
}
