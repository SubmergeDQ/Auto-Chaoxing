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

  /// 卡片里给出的「已通过」标记。null 表示卡片没给这个字段（语义待真实账号确认），
  /// 不能当 false 用——没给只代表我们不知道，不代表平台没通过。
  final bool? passed;

  bool get isVideo => type == 'video' && objectId.isNotEmpty;

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
