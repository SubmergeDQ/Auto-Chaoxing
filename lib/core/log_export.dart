// 执行日志导出：把一次执行摊成一段可复制的纯文本，顺手把不该外带的信息抹掉。
//
// 为什么单独一个文件：这是纯字符串处理，放 core 下能直接被纯 Dart 单测覆盖，
// 也让「导出内容里不能出现手机号 / cookie」这条验收要求有一个可测的落点。
import 'task_runner.dart';

/// 脱敏规则（保守：宁可多抹，不可漏抹）。
///
/// - 手机号：`13800138000` → `138****8000`
/// - 32 位十六进制：cookie、`enc`、`dtoken` 常见形态 → `<已隐去>`
/// - 敏感键值对：`uid=…`、`userid=…`、`token=…`、`enc=…` 等 → 保留键名、值抹掉
String maskSensitive(String text) {
  String out = text;

  // 手机号：前后不能再接数字，避免把更长的数字串切错。
  out = out.replaceAllMapped(
    RegExp(r'(?<!\d)(1[3-9]\d)(\d{4})(\d{4})(?!\d)'),
    (Match m) => '${m.group(1)}****${m.group(3)}',
  );

  // 32 位十六进制：典型的是 md5 签名、cookie 值、dtoken。
  out = out.replaceAll(RegExp(r'\b[0-9a-fA-F]{32}\b'), '<已隐去>');

  // 键值对：只抹值，保留键名，方便对照是哪一类信息。
  out = out.replaceAllMapped(
    RegExp(
      r'\b(uid|userid|_uid|token|dtoken|enc|cookie|jsessionid|sessionid|sign|pwd|password)=([^\s&,;，。）（)]+)',
      caseSensitive: false,
    ),
    (Match m) => '${m.group(1)}=***',
  );

  return out;
}

/// 阶段的中文说法。与执行页上的徽章保持一致，导出文本才对得上截图。
String phaseLabel(TaskPhase phase) => switch (phase) {
      TaskPhase.idle => '未开始',
      TaskPhase.preparing => '准备中',
      TaskPhase.running => '运行中',
      TaskPhase.succeeded => '本次执行完成',
      TaskPhase.failed => '部分未通过',
      TaskPhase.needsAttention => '需要人工',
      TaskPhase.stopped => '已停止',
    };

/// 把一次执行拼成可读文本。`dropped` 表示日志被上限截掉的条数，> 0 时在文末说明。
String formatRunLog({
  required String courseName,
  required String chapterTitle,
  required TaskPhase phase,
  required String summary,
  required List<TaskLog> logs,
  DateTime? startedAt,
  DateTime? finishedAt,
  int dropped = 0,
  DateTime? exportedAt,
}) {
  final DateTime now = exportedAt ?? DateTime.now();
  final StringBuffer b = StringBuffer()
    ..writeln('Auto-Chaoxing 执行日志')
    ..writeln('导出于 ${_stamp(now)}')
    ..writeln();

  if (courseName.isNotEmpty) b.writeln('课程：$courseName');
  if (chapterTitle.isNotEmpty) b.writeln('章节：$chapterTitle');
  if (startedAt != null) b.writeln('开始：${_stamp(startedAt)}');
  if (finishedAt != null) b.writeln('结束：${_stamp(finishedAt)}');
  b.writeln('结果：${phaseLabel(phase)}');
  if (summary.isNotEmpty) b.writeln('统计：$summary');

  b
    ..writeln()
    ..writeln('—— 日志 ——');
  if (logs.isEmpty) {
    b.writeln('（没有日志）');
  } else {
    for (final TaskLog log in logs) {
      // 级别前缀与界面一致，方便对照：警告 / 错误才写出来，其余靠时间对齐。
      final String tag = switch (log.level) {
        'warn' => '[警告] ',
        'error' => '[错误] ',
        _ => '',
      };
      b.writeln('${_clock(log.at)} $tag${log.message}');
    }
  }
  if (dropped > 0) {
    b
      ..writeln()
      ..writeln('（日志只保留最近 ${logs.length} 条，另有 $dropped 条更早的未记录）');
  }
  b
    ..writeln()
    ..writeln('说明：手机号、令牌与签名已隐去；本文件不包含 cookie。');

  return maskSensitive(b.toString());
}

String _two(int v) => v.toString().padLeft(2, '0');

String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String _stamp(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_clock(t)}';
