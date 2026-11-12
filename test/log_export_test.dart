import 'package:auto_chaoxing/core/log_export.dart';
import 'package:auto_chaoxing/core/task_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('maskSensitive', () {
    test('手机号只留前三后四', () {
      expect(maskSensitive('账号 13800138000 已登录'), '账号 138****8000 已登录');
    });

    test('更长的数字串里不误切出手机号', () {
      // 18 位数字里含 11 位手机号形态，前后接数字时不该被当成手机号处理。
      expect(maskSensitive('订单 913800138000123456'), '订单 913800138000123456');
    });

    test('32 位十六进制整体隐去', () {
      const String md5 = 'd41d8cd98f00b204e9800998ecf8427e';
      expect(maskSensitive('enc=$md5'), 'enc=***');
      expect(maskSensitive('签名 $md5 已发送'), '签名 <已隐去> 已发送');
    });

    test('敏感键值对保留键名、抹掉值', () {
      expect(
        maskSensitive('userid=10086&uid=10086&token=abc123'),
        'userid=***&uid=***&token=***',
      );
    });

    test('普通日志文本原样保留', () {
      const String line = '通过：1.1 映射与函数';
      expect(maskSensitive(line), line);
      expect(maskSensitive('已上报 5:00 / 10:00'), '已上报 5:00 / 10:00');
    });
  });

  group('formatRunLog', () {
    final DateTime started = DateTime(2026, 11, 12, 19, 40, 8);
    final DateTime finished = DateTime(2026, 11, 12, 19, 44, 11);

    List<TaskLog> demoLogs() => <TaskLog>[
          TaskLog('开始处理「第一章 函数与极限」，共 2 个视频任务点', at: started),
          TaskLog('通过：1.1 映射与函数', at: started.add(const Duration(seconds: 12))),
          TaskLog('未通过：1.2 数列的极限（可能有人脸抽检或倍速限制）',
              level: 'warn', at: started.add(const Duration(seconds: 30))),
          TaskLog('登录已失效', level: 'error', at: finished),
        ];

    test('抬头写清课程、章节、起止与结果', () {
      final String text = formatRunLog(
        courseName: '高等数学（上）',
        chapterTitle: '第一章 函数与极限',
        phase: TaskPhase.failed,
        summary: '1 / 2 个任务点已通过',
        logs: demoLogs(),
        startedAt: started,
        finishedAt: finished,
        exportedAt: DateTime(2026, 11, 12, 20, 0, 0),
      );

      expect(text, contains('Auto-Chaoxing 执行日志'));
      expect(text, contains('导出于 2026-11-12 20:00:00'));
      expect(text, contains('课程：高等数学（上）'));
      expect(text, contains('章节：第一章 函数与极限'));
      expect(text, contains('开始：2026-11-12 19:40:08'));
      expect(text, contains('结束：2026-11-12 19:44:11'));
      expect(text, contains('结果：部分未通过'));
      expect(text, contains('统计：1 / 2 个任务点已通过'));
    });

    test('逐条日志带时分秒，警告与错误带级别前缀', () {
      final String text = formatRunLog(
        courseName: '高等数学（上）',
        chapterTitle: '第一章 函数与极限',
        phase: TaskPhase.needsAttention,
        summary: '1 / 2 个任务点已通过',
        logs: demoLogs(),
        startedAt: started,
      );

      expect(text, contains('19:40:08 开始处理「第一章 函数与极限」'));
      expect(text, contains('19:40:20 通过：1.1 映射与函数'));
      expect(text, contains('19:40:38 [警告] 未通过：1.2 数列的极限'));
      expect(text, contains('[错误] 登录已失效'));
    });

    test('没有日志时不留空白', () {
      final String text = formatRunLog(
        courseName: '高等数学（上）',
        chapterTitle: '第一章 函数与极限',
        phase: TaskPhase.stopped,
        summary: '',
        logs: const <TaskLog>[],
      );

      expect(text, contains('（没有日志）'));
      expect(text, contains('结果：已停止'));
    });

    test('日志被上限截断时在文末说明条数', () {
      final String text = formatRunLog(
        courseName: '高等数学（上）',
        chapterTitle: '第一章 函数与极限',
        phase: TaskPhase.succeeded,
        summary: '2 / 2 个任务点已通过',
        logs: demoLogs(),
        dropped: 36,
      );

      expect(text, contains('另有 36 条更早的未记录'));
    });

    test('导出文本里不出现原始手机号与令牌', () {
      final String text = formatRunLog(
        courseName: '高等数学（上）',
        chapterTitle: '第一章 函数与极限',
        phase: TaskPhase.succeeded,
        summary: '2 / 2 个任务点已通过',
        logs: <TaskLog>[
          TaskLog('登录 13800138000 成功，uid=10086', at: started),
        ],
      );

      expect(text, isNot(contains('13800138000')));
      expect(text, isNot(contains('uid=10086')));
      expect(text, contains('138****8000'));
    });
  });
}
