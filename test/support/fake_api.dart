// 可注入的协议假实现：只返回预设数据，不发任何网络请求。
// 供状态测试、Widget 测试与视觉取证共用，保证截图里的状态是确定的。
import 'dart:async';

import 'package:auto_chaoxing/core/chaoxing_api.dart';
import 'package:auto_chaoxing/core/models.dart';

class FakeChaoxingApi extends ChaoxingApi {
  FakeChaoxingApi({
    Profile? profile,
    this.courses = const <Course>[],
    this.chapters = const <Chapter>[],
    this.points = const <TaskPoint>[],
    this.loginError,
    this.loginErrorCode = 'api',
    this.coursesError,
    this.chaptersError,
    this.cardsErrorCode,
  }) : demoProfile = profile ??
            const Profile(
              uid: '10086',
              name: '林知远',
              fid: '666',
              school: '示例大学',
            );

  final Profile demoProfile;
  List<Course> courses;
  List<Chapter> chapters;
  List<TaskPoint> points;
  String? loginError;
  String loginErrorCode;
  String? coursesError;
  String? chaptersError;
  String? cardsErrorCode;

  /// 视频总时长（秒）。默认 120，按 60 秒步长每个任务点上报 3 次。
  int videoSeconds = 120;

  /// 这些 objectId 对应的任务点永远判为未通过，用来覆盖失败分支。
  final Set<String> neverPass = <String>{};

  /// 设置后，第一次上报会挂起，测试可在运行中调用停止。
  Completer<void>? reportGate;

  /// 设为 true 时所有上报都返回登录失效；设为 >=0 时在 N 次上报后失效。
  bool authExpiredOnReport = false;
  int authExpiredAfterReports = -1;

  int loginCalls = 0;
  int coursesCalls = 0;
  int chaptersCalls = 0;
  int cardsCalls = 0;
  int reportCalls = 0;
  int statusCalls = 0;

  @override
  Future<Result<Profile>> login(String username, String password) async {
    loginCalls++;
    if (loginError != null) return Err<Profile>(loginErrorCode, loginError!);
    return Ok<Profile>(demoProfile);
  }

  @override
  Future<Result<Profile>> fetchProfile() async {
    return Ok<Profile>(demoProfile);
  }

  @override
  Future<Result<List<Course>>> fetchCourses() async {
    coursesCalls++;
    if (coursesError != null) return Err<List<Course>>('network', coursesError!);
    return Ok<List<Course>>(courses);
  }

  @override
  Future<Result<List<Chapter>>> fetchChapters({
    required String courseId,
    required String classId,
    String cpi = '',
  }) async {
    chaptersCalls++;
    if (chaptersError != null) return Err<List<Chapter>>('network', chaptersError!);
    return Ok<List<Chapter>>(chapters);
  }

  @override
  Future<Result<ChapterCards>> fetchCards({
    required String courseId,
    required String classId,
    required String chapterId,
    String cpi = '',
    int page = 0,
  }) async {
    cardsCalls++;
    if (cardsErrorCode == 'locked') {
      // 与真实 API 的 locked 文案保持一致，避免假实现给出与线上不同的提示。
      return const Err<ChapterCards>('locked', '章节未开放：上一章未完成或测验未提交');
    }
    if (cardsErrorCode != null) {
      return Err<ChapterCards>(cardsErrorCode!, '卡片读取失败');
    }
    return Ok<ChapterCards>(
      ChapterCards(
        reportUrl: 'https://mooc1.chaoxing.com/multimedia/log',
        fid: '666',
        userId: demoProfile.uid,
        points: points,
      ),
    );
  }

  @override
  Future<Result<VideoStatus>> videoStatus(String objectId, String fid) async {
    statusCalls++;
    if (videoSeconds <= 0) return const Err<VideoStatus>('api', '视频时长异常');
    return Ok<VideoStatus>(
      VideoStatus(objectId: objectId, duration: videoSeconds, dtoken: 'dt-$objectId'),
    );
  }

  @override
  Future<Result<bool>> reportProgress({
    required String reportUrl,
    required String dtoken,
    required TaskPoint point,
    required String classId,
    required String uid,
    required int playTime,
    required int duration,
  }) async {
    reportCalls++;
    final Completer<void>? gate = reportGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    if (authExpiredOnReport ||
        (authExpiredAfterReports >= 0 && reportCalls > authExpiredAfterReports)) {
      return const Err<bool>('authExpired', '登录已失效');
    }
    if (neverPass.contains(point.objectId)) return const Ok<bool>(false);
    return Ok<bool>(playTime >= duration);
  }
}

const List<Course> kDemoCourses = <Course>[
  Course(
    courseId: '2410001',
    classId: '88001',
    cpi: '126843',
    name: '高等数学（上）',
    teacher: '李文博',
  ),
  Course(
    courseId: '2410002',
    classId: '88002',
    cpi: '126844',
    name: '设计与思维',
    teacher: '周敏',
  ),
  Course(
    courseId: '2410003',
    classId: '88003',
    cpi: '126845',
    name: '空间光环境基础',
    teacher: '陈昱',
  ),
  Course(
    courseId: '2410004',
    classId: '88004',
    cpi: '126846',
    name: '大学英语（二）',
    teacher: '王琳',
    archived: true,
  ),
];

const List<Chapter> kDemoChapters = <Chapter>[
  Chapter(chapterId: '510001', title: '第一章 函数与极限'),
  Chapter(chapterId: '510002', title: '第二章 导数与微分'),
  Chapter(chapterId: '510003', title: '第三章 微分中值定理'),
  Chapter(chapterId: '510004', title: '第四章 不定积分'),
];

const List<TaskPoint> kDemoPoints = <TaskPoint>[
  TaskPoint(type: 'video', jobId: 'j-101', name: '1.1 映射与函数', objectId: 'o-101'),
  TaskPoint(type: 'document', jobId: 'j-102', name: '第一章课程讲义.pdf'),
  TaskPoint(type: 'video', jobId: 'j-103', name: '1.2 数列的极限', objectId: 'o-103'),
  TaskPoint(type: 'workid', jobId: 'j-104', name: '第一章章节作业'),
];
