import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/main.dart';
import 'package:auto_chaoxing/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  AppState signedInState({List<Course> courses = kDemoCourses}) {
    final AppState state = AppState(api: FakeChaoxingApi(courses: courses));
    state.profile = const Profile(
      uid: '10086',
      name: '林知远',
      fid: '666',
      school: '示例大学',
    );
    state.coursesState = LoadState.ready;
    state.courses = courses;
    return state;
  }

  group('课程工作台', () {
    testWidgets('未登录时给出连接入口与边界说明', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: AppState(api: FakeChaoxingApi())));

      expect(find.text('先连接你的学习通账号'), findsOneWidget);
      expect(find.text('连接账号'), findsOneWidget);
      expect(find.textContaining('请只用于你自己的账号'), findsOneWidget);
    });

    testWidgets('已登录渲染课程列表与汇总指标', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState()));

      expect(find.text('高等数学（上）'), findsOneWidget);
      expect(find.text('空间光环境基础'), findsOneWidget);
      expect(find.text('在修课程'), findsOneWidget);
      expect(find.text('已归档'), findsWidgets);
      expect(find.text('已连接'), findsOneWidget);
    });

    testWidgets('课程为空时显示空态而不是假数据', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState(courses: const <Course>[])));

      expect(find.text('这个账号还没有课程'), findsOneWidget);
      expect(find.text('高等数学（上）'), findsNothing);
    });

    testWidgets('读取失败显示错误原因与重试', (WidgetTester tester) async {
      final AppState state = signedInState();
      state.coursesState = LoadState.error;
      state.coursesError = '连接超时';
      await tester.pumpWidget(AutoChaoxingApp(state: state));

      expect(find.text('课程列表读取失败'), findsOneWidget);
      expect(find.text('连接超时'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  group('辅助页面', () {
    testWidgets('协议自检两行向量都通过', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState()));

      await tester.tap(find.text('自检'));
      await tester.pump();

      expect(find.text('协议自检通过'), findsOneWidget);
      expect(find.text('PASS'), findsNWidgets(2));
      expect(find.text('AES-CBC 登录加密'), findsOneWidget);
    });

    testWidgets('设置页展示运行约束与断开连接', (WidgetTester tester) async {
      await tester.pumpWidget(AutoChaoxingApp(state: signedInState()));

      await tester.tap(find.text('设置'));
      await tester.pump();

      expect(find.text('单账号串行'), findsOneWidget);
      expect(find.text('断开连接'), findsOneWidget);

      final Finder disconnect = find.text('断开连接');
      await tester.ensureVisible(disconnect);
      await tester.pump();
      await tester.tap(disconnect);
      await tester.pump();

      expect(find.text('断开连接'), findsNothing);
      expect(find.text('未连接账号'), findsNWidgets(2), reason: '顶栏与账号卡片各一处');
    });
  });
}
