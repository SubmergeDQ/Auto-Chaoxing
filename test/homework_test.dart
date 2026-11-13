import 'package:auto_chaoxing/core/homework_rules.dart';
import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/state/homework_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  group('作业列表解析', () {
    test('data.list 结构按 workId 解析，已交只认明确字段', () {
      final List<HomeworkItem>? items = parseHomeworkList('''
        {"data":{"list":[
          {"workId":1001,"name":"第一章作业","endTime":"2026-12-01 23:59:00","completed":true},
          {"workId":1002,"name":"第二章作业","endTime":1767225600000,"isSubmit":0},
          {"id":1003,"title":"无 workId","status":2}
        ]}}
      ''');

      expect(items, isNotNull);
      expect(items, hasLength(3));
      expect(items![0].workId, '1001');
      expect(items[0].completed, isTrue);
      expect(items[1].completed, isFalse);
      expect(items[1].endAt, isNotNull);
      // status 语义未确认，不能当已交。
      expect(items[2].completed, isNull);
      expect(items[2].endAt, isNull);
    });

    test('data 直接是数组也能解析，认不出 workId 的条目丢弃', () {
      final List<HomeworkItem>? items = parseHomeworkList('''
        {"data":[{"workid":"2001","workName":"实验报告"},{"name":"没有 id"}]}
      ''');

      expect(items, hasLength(1));
      expect(items!.first.name, '实验报告');
    });

    test('无法解析时返回 null，空列表返回空数组', () {
      expect(parseHomeworkList('not json'), isNull);
      expect(parseHomeworkList('{"msg":"no data"}'), isNull);
      expect(parseHomeworkList('{"data":{"list":[]}}'), isEmpty);
    });

    test('作答页地址带课程、班级与 cpi', () {
      final String url = homeworkPageUrl(course: kDemoCourses.first, workId: '9001');
      expect(url, contains('workId=9001'));
      expect(url, contains('courseId=2410001'));
      expect(url, contains('classId=88001'));
      expect(url, contains('cpi=126843'));
    });
  });

  group('HomeworkController', () {
    test('打开课程后加载作业列表', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(
        homeworks: const <HomeworkItem>[
          HomeworkItem(workId: '1', name: '第一章作业', completed: false),
        ],
      );
      final HomeworkController controller =
          HomeworkController(api: api, onChanged: () {});

      await controller.open(kDemoCourses.first);

      expect(controller.loading, isFalse);
      expect(controller.items, hasLength(1));
      expect(controller.items.first.name, '第一章作业');
      expect(api.homeworksCalls, 1);

      controller.dispose();
    });

    test('读取失败保留可读错误', () async {
      final FakeChaoxingApi api = FakeChaoxingApi()
        ..homeworksError = '连接超时';
      final HomeworkController controller =
          HomeworkController(api: api, onChanged: () {});

      await controller.open(kDemoCourses.first);

      expect(controller.error, '连接超时');
      expect(controller.items, isEmpty);

      controller.dispose();
    });

    test('断开账号后清空列表', () async {
      final FakeChaoxingApi api = FakeChaoxingApi(
        homeworks: const <HomeworkItem>[HomeworkItem(workId: '1', name: '作业')],
      );
      final HomeworkController controller =
          HomeworkController(api: api, onChanged: () {});
      await controller.open(kDemoCourses.first);

      controller.reset();

      expect(controller.course, isNull);
      expect(controller.items, isEmpty);

      controller.dispose();
    });
  });
}
