// 学习通 HTTP 客户端：只负责请求、Cookie、解析与错误归一。
// 不包含重试策略与业务循环（那是 task_runner 的事）。
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'crypto.dart';
import 'models.dart';

const String kMobileUa =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/// 登录失效的判定特征串。响应是 HTML 时先过一遍这个，再谈解析。
const List<String> _authExpiredMarkers = <String>[
  'passport2.chaoxing.com/login',
  'id="loginForm"',
  'id="phone-mobile"',
];

class ChaoxingApi {
  ChaoxingApi({CookieJar? cookieJar})
      : cookieJar = cookieJar ?? CookieJar(),
        _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 25),
            followRedirects: true,
            validateStatus: (int? s) => s != null && s < 500,
            headers: <String, dynamic>{
              'User-Agent': kMobileUa,
              'Accept': '*/*',
              'Accept-Language': 'zh-CN,zh;q=0.9',
              'X-Requested-With': 'com.chaoxing.mobile',
            },
          ),
        ) {
    // 这里必须用字段而不是构造参数：参数是 CookieJar?，字段已保证非空。
    _dio.interceptors.add(CookieManager(this.cookieJar));
  }

  final CookieJar cookieJar;
  final Dio _dio;

  Profile? profile;

  /// 登录：账号密码先本地 AES-CBC 加密，再提交。
  Future<Result<Profile>> login(String username, String password) async {
    try {
      final Response<String> resp = await _dio.post<String>(
        'https://passport2.chaoxing.com/fanyalogin',
        data: <String, dynamic>{
          'fid': '-1',
          'refer': 'https://i.chaoxing.com',
          't': 'true',
          'forbidotherlogin': '0',
          'validate': '',
          'uname': aesCbcBase64(username.trim()),
          'password': aesCbcBase64(password),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final Map<String, dynamic>? json = _tryJson(resp.data);
      if (json == null) {
        return const Err<Profile>('parse', '登录响应无法解析');
      }
      if (json['status'] == true) {
        final Result<Profile> me = await fetchProfile();
        return me;
      }
      final String msg = '${json['msg2'] ?? json['mes'] ?? json['msg'] ?? '登录失败'}';
      if (json['needVcode'] == true ||
          json['containTwoFactorLogin'] == true ||
          json['weakpwd'] == true) {
        return Err<Profile>('needsAttention', msg.isEmpty ? '需要验证码或二次验证' : msg);
      }
      return Err<Profile>('api', msg);
    } on DioException catch (e) {
      return Err<Profile>('network', e.message ?? '网络错误');
    }
  }

  Future<Result<Profile>> fetchProfile() async {
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://sso.chaoxing.com/apis/login/userLogin4Uname.do',
      );
      final Map<String, dynamic>? json = _tryJson(resp.data);
      if (json == null || json['result'] != 1) {
        return const Err<Profile>('authExpired', '登录已失效');
      }
      final Map<String, dynamic> msg = (json['msg'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final Profile p = Profile.fromJson(msg);
      if (p.uid.isEmpty) {
        return const Err<Profile>('authExpired', '未取到账号信息');
      }
      profile = p;
      return Ok<Profile>(p);
    } on DioException catch (e) {
      return Err<Profile>('network', e.message ?? '网络错误');
    }
  }

  Future<Result<List<Course>>> fetchCourses() async {
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://mooc1-api.chaoxing.com/mycourse/backclazzdata',
        queryParameters: <String, dynamic>{'view': 'json', 'rss': '1'},
      );
      final String body = resp.data ?? '';
      if (_looksLikeLogin(body)) {
        return const Err<List<Course>>('authExpired', '登录已失效');
      }
      final Map<String, dynamic>? json = _tryJson(body);
      if (json == null) return const Err<List<Course>>('parse', '课程列表无法解析');
      final List<Course> out = <Course>[];
      final List<dynamic> channels =
          (json['channelList'] ?? json['channel'] ?? <dynamic>[]) as List<dynamic>;
      for (final dynamic ch in channels) {
        final Map<String, dynamic> channel = (ch as Map).cast<String, dynamic>();
        final Map<String, dynamic> content =
            (channel['content'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final Map<String, dynamic> courseWrap =
            (content['course'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final List<dynamic> data = (courseWrap['data'] ?? <dynamic>[]) as List<dynamic>;
        if (data.isEmpty) continue;
        final Map<String, dynamic> c = (data.first as Map).cast<String, dynamic>();
        final String courseId = '${c['id'] ?? ''}';
        final String classId = '${content['id'] ?? ''}';
        if (!_isDigits(courseId) || !_isDigits(classId)) continue;
        out.add(
          Course(
            courseId: courseId,
            classId: classId,
            cpi: '${content['cpi'] ?? channel['cpi'] ?? ''}',
            name: '${c['name'] ?? '未命名课程'}',
            teacher: '${c['teacherfactor'] ?? ''}',
            archived: content['isFiled'] == 1 || content['isretire'] == 1,
          ),
        );
      }
      return Ok<List<Course>>(out);
    } on DioException catch (e) {
      return Err<List<Course>>('network', e.message ?? '网络错误');
    }
  }

  /// 章节卡片。返回 null 表示章节未开放（上一章未完成/测验未交），不是 bug。
  Future<Result<ChapterCards>> fetchCards({
    required String courseId,
    required String classId,
    required String chapterId,
    String cpi = '',
    int page = 0,
  }) async {
    final String ref = 'https://mooc1.chaoxing.com/mycourse/studentstudy'
        '?chapterId=$chapterId&courseId=$courseId&clazzid=$classId&cpi=$cpi'
        '&enc=${md5Hex('${DateTime.now().microsecondsSinceEpoch}')}&mooc2=1';
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://mooc1.chaoxing.com/knowledge/cards',
        queryParameters: <String, dynamic>{
          'clazzid': classId,
          'courseid': courseId,
          'knowledgeid': chapterId,
          'num': '$page',
          'ut': 's',
          'cpi': cpi,
          'v': '20160407-1',
        },
        options: Options(headers: <String, dynamic>{'Referer': ref}),
      );
      final String html = resp.data ?? '';
      if (_looksLikeLogin(html)) {
        return const Err<ChapterCards>('authExpired', '登录已失效');
      }
      final Map<String, dynamic>? marg = extractMarg(html);
      if (marg == null) {
        return const Err<ChapterCards>('locked', '章节未开放：上一章未完成或测验未提交');
      }
      final Map<String, dynamic> defaults =
          (marg['defaults'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final List<TaskPoint> points = <TaskPoint>[];
      for (final dynamic raw in (marg['attachments'] ?? <dynamic>[]) as List<dynamic>) {
        final Map<String, dynamic> att = (raw as Map).cast<String, dynamic>();
        if (att['job'] != true) continue;
        final Map<String, dynamic> prop =
            (att['property'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        points.add(
          TaskPoint(
            type: '${att['type'] ?? ''}',
            jobId: '${att['jobid'] ?? ''}',
            name: '${prop['name'] ?? ''}',
            objectId: '${prop['objectid'] ?? ''}',
            otherInfo: '${att['otherInfo'] ?? ''}',
            rt: '${prop['rt'] ?? '0.9'}',
            attDuration: '${att['attDuration'] ?? '0'}',
            attDurationEnc: '${att['attDurationEnc'] ?? ''}',
            videoFaceCaptureEnc: '${att['videoFaceCaptureEnc'] ?? ''}',
          ),
        );
      }
      return Ok<ChapterCards>(
        ChapterCards(
          reportUrl: '${defaults['reportUrl'] ?? ''}',
          fid: '${defaults['fid'] ?? '666'}',
          userId: '${defaults['userid'] ?? ''}',
          points: points,
        ),
      );
    } on DioException catch (e) {
      return Err<ChapterCards>('network', e.message ?? '网络错误');
    }
  }

  Future<Result<VideoStatus>> videoStatus(String objectId, String fid) async {
    try {
      final Response<String> resp = await _dio.get<String>(
        'https://mooc1.chaoxing.com/ananas/status/$objectId',
        queryParameters: <String, dynamic>{
          'k': fid,
          'flag': 'normal',
          '_dc': '${DateTime.now().millisecondsSinceEpoch}',
        },
        options: Options(
          headers: <String, dynamic>{
            'Referer': 'https://mooc1.chaoxing.com/ananas/modules/video/index.html?v=2024',
          },
        ),
      );
      final Map<String, dynamic>? json = _tryJson(resp.data);
      if (json == null || json['status'] != 'success') {
        return const Err<VideoStatus>('api', '视频不可用');
      }
      final int duration = int.tryParse('${json['duration'] ?? 0}') ?? 0;
      if (duration <= 0) return const Err<VideoStatus>('api', '视频时长异常');
      return Ok<VideoStatus>(
        VideoStatus(
          objectId: '${json['objectid'] ?? objectId}',
          duration: duration,
          dtoken: '${json['dtoken'] ?? ''}',
        ),
      );
    } on DioException catch (e) {
      return Err<VideoStatus>('network', e.message ?? '网络错误');
    }
  }

  /// 上报一次进度。返回 true 表示平台判定该任务点完成。
  Future<Result<bool>> reportProgress({
    required String reportUrl,
    required String dtoken,
    required TaskPoint point,
    required String classId,
    required String uid,
    required int playTime,
    required int duration,
  }) async {
    final String enc = progressEnc(
      classId: classId,
      uid: uid,
      jobId: point.jobId,
      objectId: point.objectId,
      playTime: playTime,
      duration: duration,
    );
    final bool dragEnd = playTime >= duration;
    final String url = '$reportUrl/$dtoken';
    try {
      final Response<String> resp = await _dio.get<String>(
        url,
        queryParameters: <String, dynamic>{
          'clazzId': classId,
          'playingTime': '$playTime',
          'duration': '$duration',
          'clipTime': '0_$duration',
          'objectId': point.objectId,
          'otherInfo': point.otherInfo,
          'jobid': point.jobId,
          'userid': uid,
          'isdrag': dragEnd ? '4' : '3',
          'view': 'pc',
          'enc': enc,
          'rt': point.rt,
          'videoFaceCaptureEnc': point.videoFaceCaptureEnc,
          'dtype': 'Video',
          '_t': '${DateTime.now().millisecondsSinceEpoch}',
          'attDuration': point.attDuration,
          'attDurationEnc': point.attDurationEnc,
        },
        options: Options(
          headers: <String, dynamic>{
            'Referer': 'https://mooc1.chaoxing.com/ananas/modules/video/index.html?v=2024',
          },
        ),
      );
      final Map<String, dynamic>? json = _tryJson(resp.data);
      if (json == null) return const Err<bool>('parse', '进度响应无法解析');
      return Ok<bool>(json['isPassed'] == true);
    } on DioException catch (e) {
      return Err<bool>('network', e.message ?? '网络错误');
    }
  }

  // ---------------------------------------------------------------- 工具

  bool _looksLikeLogin(String body) =>
      _authExpiredMarkers.any((String m) => body.contains(m));

  static bool _isDigits(String s) => s.isNotEmpty && int.tryParse(s) != null;

  static Map<String, dynamic>? _tryJson(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final dynamic v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
