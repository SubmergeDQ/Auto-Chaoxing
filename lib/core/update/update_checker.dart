// 从 GitHub Releases 取最新版本。只负责请求与解析，不做节流、不做下载。
import 'package:dio/dio.dart';

import '../models.dart';
import 'app_release.dart';

/// 仓库坐标。换仓库只改这里。
const String kReleaseOwner = 'SubmergeDQ';
const String kReleaseRepo = 'Auto-Chaoxing';

/// 仓库主页，关于页展示用。
const String kRepoUrl = 'https://github.com/$kReleaseOwner/$kReleaseRepo';

class UpdateChecker {
  UpdateChecker({Dio? dio, this.owner = kReleaseOwner, this.repo = kReleaseRepo})
      : _dio = dio ??
            Dio(
              BaseOptions(
                // 检查更新是锦上添花，不该让用户等：8 秒拿不到就当网络不行。
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 10),
                validateStatus: (int? s) => s != null && s < 500,
                headers: <String, dynamic>{
                  'Accept': 'application/vnd.github+json',
                  'User-Agent': 'Auto-Chaoxing-updater',
                },
              ),
            );

  final Dio _dio;
  final String owner;
  final String repo;

  String get latestEndpoint => 'https://api.github.com/repos/$owner/$repo/releases/latest';

  /// Ok(null) 表示仓库还没有任何正式发布版本——这不是错误，
  /// 首次发版前就是这个状态，界面应该说「还没有发布版本」而不是报错。
  Future<Result<AppRelease?>> fetchLatest() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(latestEndpoint);
      if (resp.statusCode == 404) return const Ok<AppRelease?>(null);
      final dynamic data = resp.data;
      if (data is! Map) {
        return const Err<AppRelease?>('parse', '发布信息无法解析');
      }
      final Map<String, dynamic> json = data.cast<String, dynamic>();
      // GitHub 在限流时返回 message 而非 release 结构，别把它当成空版本。
      if (json.containsKey('message') && !json.containsKey('tag_name')) {
        final String msg = '${json['message']}';
        if (msg.toLowerCase().contains('rate limit')) {
          return const Err<AppRelease?>('rateLimited', 'GitHub 接口访问过于频繁，请稍后再试');
        }
        return Err<AppRelease?>('api', msg);
      }
      final AppRelease release = AppRelease.fromJson(json);
      if (release.tag.isEmpty) {
        return const Err<AppRelease?>('parse', '发布信息缺少版本号');
      }
      return Ok<AppRelease?>(release);
    } on DioException catch (e) {
      return Err<AppRelease?>('network', _message(e));
    }
  }

  static String _message(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return '连不上 GitHub，请检查网络后重试';
    }
    return '检查更新失败：${e.message ?? e.type.name}';
  }
}
