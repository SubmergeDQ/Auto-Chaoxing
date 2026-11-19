// 协议数据模型。只做数据承载，不含 IO。
import 'dart:convert';

/// 统一结果类型：core 层不用异常跨层。
sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.code, this.message, {this.raw});

  /// 机器可判的类别：authExpired / network / parse / locked / needsAttention / api
  final String code;
  final String message;
  final String? raw;

  @override
  String toString() => 'Err($code): $message';
}

class Profile {
  const Profile({
    required this.uid,
    required this.name,
    required this.fid,
    this.school = '',
  });

  final String uid;
  final String name;
  final String fid;
  final String school;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        uid: '${json['puid'] ?? ''}',
        name: '${json['name'] ?? ''}',
        fid: '${json['fid'] ?? ''}',
        school: '${json['schoolname'] ?? ''}',
      );
}

class Course {
  const Course({
    required this.courseId,
    required this.classId,
    required this.cpi,
    required this.name,
    this.teacher = '',
    this.archived = false,
  });

  final String courseId;
  final String classId;
  final String cpi;
  final String name;
  final String teacher;
  final bool archived;

  String get key => '$courseId:$classId';
}

class Chapter {
  const Chapter({required this.chapterId, required this.title});

  final String chapterId;
  final String title;
}

/// 章节卡片里的一个任务点。
class TaskPoint {
  const TaskPoint({
    required this.type,
    required this.jobId,
    required this.name,
    this.objectId = '',
    this.otherInfo = '',
    this.rt = '0.9',
    this.attDuration = '0',
    this.attDurationEnc = '',
    this.videoFaceCaptureEnc = '',
    this.jtoken = '',
    this.microTopicId = 0,
    this.passed,
  });

  final String type; // video / document / workid / read / live
  final String jobId;
  final String name;
  final String objectId;
  final String otherInfo;
  final String rt;
  final String attDuration;
  final String attDurationEnc;
  final String videoFaceCaptureEnc;

  /// 阅读/文档任务点的完成票据。平台完成接口（readv2/job）必带，
  /// 由卡片下发、随会话刷新；没有它就无法向平台证明这次完成是合法的。
  final String jtoken;

  /// 专题归属 id；非专题任务点为 0。完成阅读任务点时要原样带上。
  final int microTopicId;

  /// 卡片里给出的「已通过」标记。null 表示卡片没给这个字段（语义待真实账号确认），
  /// 不能当 false 用——没给只代表我们不知道，不代表平台没通过。
  final bool? passed;

  bool get isVideo => type == 'video' && objectId.isNotEmpty;

  /// 可自动完成的阅读任务点：type=read 且带 jobid 与 jtoken。
  /// 只有 `_jobid` 没有 `jobid` 的「去阅读」链接不是任务点，平台不追踪它的完成。
  bool get isRead => type == 'read' && jobId.isNotEmpty && jtoken.isNotEmpty;

  /// 本客户端能自动执行的任务点（视频 + 阅读）。文档/作业/测验仍需手机端完成。
  bool get isExecutable => isVideo || isRead;

  /// 平台记录的累计观看秒数（来自卡片 `attDuration`）。
  ///
  /// 用途只有一个：有值时从这一段继续上报，省掉已经看过的部分。字段为 0 或解析失败时
  /// 行为与从前一致（从 0 开始），因此它是纯增益的，不依赖这个字段一定存在。
  int get watchedSeconds => int.tryParse(attDuration.trim()) ?? 0;

  /// 是否具备续跑依据：平台说看了一部分，但还不能确定已通过。
  bool get canResume => passed != true && watchedSeconds > 0;
}

/// knowledge/cards 返回的 defaults。
class ChapterCards {
  const ChapterCards({
    required this.reportUrl,
    required this.fid,
    required this.userId,
    required this.points,
  });

  final String reportUrl;
  final String fid;
  final String userId;
  final List<TaskPoint> points;
}

class VideoStatus {
  const VideoStatus({
    required this.objectId,
    required this.duration,
    required this.dtoken,
  });

  final String objectId;
  final int duration; // 秒
  final String dtoken;
}

/// 一条签到 / 签退活动（来自 activelist）。
class SignActivity {
  const SignActivity({
    required this.activeId,
    required this.name,
    required this.type,
    required this.status,
    this.startAt,
    this.endAt,
    this.otherId = '',
    this.ext = '',
  });

  final String activeId;
  final String name;

  /// 2 = 签到，74 = 签退。其余类型不归本客户端处理。
  final int type;

  /// 平台原样返回的状态值。语义未在真实账号上确认，界面只用时间窗判断。
  final int status;

  final DateTime? startAt;
  final DateTime? endAt;

  /// 活动所属的课程内对象 id（真实响应里可能是 otherId）。
  final String otherId;

  /// 会话数据，短时效；预签到必须当场带上，不能缓存复用。
  final String ext;

  bool get isSignIn => type == 2;

  bool get isSignBack => type == 74;

  /// 是否处在可签时间窗内。`endAt` 缺失时按「未知」处理，不当作可签。
  bool isOpenAt(DateTime now) {
    final DateTime? start = startAt;
    final DateTime? end = endAt;
    if (start == null || end == null) return false;
    return !now.isBefore(start) && !now.isAfter(end);
  }

  /// 时间窗已过。用于把「还没开始」和「已经结束」分开，而不是都显示成「不可签」。
  bool isExpiredAt(DateTime now) {
    final DateTime? end = endAt;
    return end != null && now.isAfter(end);
  }
}

/// 一次签到的结果分类。UI 按它决定说「成功 / 已经签过 / 要人脸 / 要验证码」。
enum SignOutcome {
  success,
  alreadySigned,
  expired,
  notStarted,
  needFace,
  needValidate,
  needLocation,
  error,
}

class SignAttempt {
  const SignAttempt(this.outcome, {this.message = ''});

  final SignOutcome outcome;
  final String message;

  bool get ok => outcome == SignOutcome.success || outcome == SignOutcome.alreadySigned;
}

/// 一条作业（来自 work/task-list）。
class HomeworkItem {
  const HomeworkItem({
    required this.workId,
    required this.name,
    this.endAt,
    this.completed,
  });

  final String workId;
  final String name;
  final DateTime? endAt;

  /// 平台是否标记已交。null 表示响应里没给可识别的字段——
  /// 不能当 false 用，界面会显示「状态未知」而不是「未交」。
  final bool? completed;

  bool get expired {
    final DateTime? end = endAt;
    return end != null && DateTime.now().isAfter(end);
  }
}

/// 作业/章节测验的题型。数值与平台 `answertype` 一致。
enum HomeworkQuestionType {
  single(0),
  multiple(1),
  fill(2),
  judge(3),
  short(4),
  unknown(-1);

  const HomeworkQuestionType(this.code);

  final int code;

  static HomeworkQuestionType fromCode(int code) {
    for (final HomeworkQuestionType t in HomeworkQuestionType.values) {
      if (t.code == code) return t;
    }
    return HomeworkQuestionType.unknown;
  }
}

class HomeworkOption {
  const HomeworkOption({
    required this.key,
    required this.text,
    this.value = '',
  });

  /// 选项字母 A/B/C/D。
  final String key;

  /// 选项正文（不含字母）。
  final String text;

  /// 判断题的 val-param（true/false）；选择题为空。
  final String value;
}

class HomeworkQuestion {
  const HomeworkQuestion({
    required this.id,
    required this.type,
    required this.text,
    this.options = const <HomeworkOption>[],
    this.blanks = const <String>[],
  });

  final String id;
  final HomeworkQuestionType type;
  final String text;
  final List<HomeworkOption> options;

  /// 填空题每个空的提交字段名（`answer<qid><n>`），按顺序排列。
  final List<String> blanks;

  bool get answerable =>
      type == HomeworkQuestionType.single ||
      type == HomeworkQuestionType.multiple ||
      type == HomeworkQuestionType.fill ||
      type == HomeworkQuestionType.judge ||
      type == HomeworkQuestionType.short;
}

/// 一份作业作答页：隐藏字段 + 识别出的题目。
///
/// 隐藏字段是平台提交接口的必填票据，页面自己也会原样回传；
/// 这里不猜字段含义，只按页面给的键值保存。
class HomeworkPaper {
  const HomeworkPaper({
    required this.sourceUrl,
    required this.fields,
    required this.questions,
  });

  final String sourceUrl;
  final Map<String, String> fields;
  final List<HomeworkQuestion> questions;

  String field(String key) => fields[key] ?? '';

  /// 题库接口用的作业 id。页面通常给 oldWorkId（题库库 id），
  /// 没有时退回 workLibraryId / workId。
  String get workId {
    for (final String key in <String>['oldWorkId', 'workLibraryId', 'workId']) {
      final String v = field(key).trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  int get answerableCount =>
      questions.where((HomeworkQuestion q) => q.answerable).length;
}

/// 作业提交的结果。`ok == null` 表示请求发出去了，但平台没有给出明确回执。
class HomeworkSubmitResult {
  const HomeworkSubmitResult({
    required this.ok,
    required this.message,
    this.raw = '',
  });

  final bool? ok;
  final String message;
  final String raw;
}

/// 从 knowledge/cards 的 HTML 里抠出 mArg JSON。
/// 页面结构：try{ ... mArg = {...}; }catch(e){ ... }
Map<String, dynamic>? extractMarg(String html) {
  final RegExp re = RegExp(r'mArg\s*=\s*(\{.+?\});\s*\}\s*catch', dotAll: true);
  final RegExpMatch? m = re.firstMatch(html);
  if (m == null) return null;
  try {
    final dynamic decoded = jsonDecode(m.group(1)!);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
