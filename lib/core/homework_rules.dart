// 作业协议里的纯规则：task-list 响应解析与作答页地址拼装。
//
// task-list 的字段名只做过部分验证，所以这里做宽松匹配：
// 认不出 workId 的条目直接丢弃；「是否已交」只认明确的 true / 1，
// 其余留 null——宁可显示「状态未知」，也不能把没交的说成交了。
import 'dart:convert';

import 'models.dart';
import 'sign_rules.dart';

/// 解析作业列表。返回 null 表示响应结构完全认不出来（而不是「没有作业」）。
List<HomeworkItem>? parseHomeworkList(String body) {
  final dynamic decoded = _tryDecode(body);
  if (decoded == null) return null;
  final List<dynamic>? rows = _findList(decoded);
  if (rows == null) return null;

  final List<HomeworkItem> out = <HomeworkItem>[];
  final Set<String> seen = <String>{};
  for (final dynamic row in rows) {
    if (row is! Map) continue;
    final Map<String, dynamic> m = row.cast<String, dynamic>();
    final String id = '${m['workId'] ?? m['workid'] ?? m['id'] ?? ''}';
    if (id.isEmpty || !seen.add(id)) continue;
    out.add(
      HomeworkItem(
        workId: id,
        name: '${m['name'] ?? m['workName'] ?? m['title'] ?? '作业 $id'}',
        endAt: parseChaoxingTime(m['endTime'] ?? m['deadline'] ?? m['end_time']),
        completed: _readCompleted(m),
      ),
    );
  }
  return out;
}

/// 作业作答页。带上课程与班级，页面自己会按登录会话取题目。
String homeworkPageUrl({required Course course, required String workId}) {
  final String cpi = course.cpi.isEmpty ? '' : '&cpi=${course.cpi}';
  return 'https://mooc1.chaoxing.com/mooc-ans/work/doHomeWorkNew'
      '?courseId=${course.courseId}&classId=${course.classId}&workId=$workId$cpi';
}

dynamic _tryDecode(String body) {
  if (body.trim().isEmpty) return null;
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

/// 已知的几种包裹形状：data 直接是数组，或 data.list / list / rows 之类。
List<dynamic>? _findList(dynamic node, [int depth = 0]) {
  if (depth > 3) return null;
  if (node is List) return node;
  if (node is! Map) return null;
  for (final String key in <String>['list', 'data', 'rows', 'items', 'workList']) {
    final dynamic value = node[key];
    if (value is List) return value;
    if (value is Map) {
      final List<dynamic>? nested = _findList(value, depth + 1);
      if (nested != null) return nested;
    }
  }
  return null;
}

bool? _readCompleted(Map<String, dynamic> m) {
  for (final String key in <String>['completed', 'isSubmit', 'submitted', 'isFinish']) {
    final dynamic v = m[key];
    if (v == true || '$v' == '1') return true;
    if (v == false || '$v' == '0') return false;
  }
  // status 的取值语义没确认，不拿它当已交标记。
  return null;
}
