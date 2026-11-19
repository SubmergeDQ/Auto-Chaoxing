// 万卷题库客户端。
//
// 协议来自九九助手公开脚本：POST api/query（表单）返回
// {code:1, data:"答案", left:剩余次数, msg:""}。题库是第三方收费服务，
// 这里只按用户自己填的 Token 查询，不内置、不转存任何凭证。
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'models.dart';

const String _kPrimaryHost = 'https://tk.wanjuantiku.com/';
const String _kProxyHost = 'https://proxy.tk.wanjuantiku.com/';

/// 九九助手 3.0.7 的版本号；题库接口用它判断脚本是否过旧。
const String _kClientVersion = '307';

const String _kBrowserUa =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

class BankAnswer {
  const BankAnswer({
    required this.text,
    this.left = -1,
    this.message = '',
  });

  final String text;
  final int left;
  final String message;
}

class WanJuanBank {
  WanJuanBank({required this.token, Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 25),
                validateStatus: (int? s) => s != null && s < 500,
                headers: <String, dynamic>{
                  'User-Agent': _kBrowserUa,
                  'Accept': '*/*',
                  'Accept-Language': 'zh-CN,zh;q=0.9',
                },
              ),
            );

  final String token;
  final Dio _dio;

  /// 已经验证可用的线路，下次优先用它。
  String? _host;

  static bool isValidToken(String token) =>
      RegExp(r'^[0-9a-z]{32}$', caseSensitive: false).hasMatch(token.trim());

  List<String> get _hosts {
    final String? known = _host;
    if (known == null) return const <String>[_kPrimaryHost, _kProxyHost];
    return known == _kPrimaryHost
        ? const <String>[_kPrimaryHost, _kProxyHost]
        : const <String>[_kProxyHost, _kPrimaryHost];
  }

  /// 校验 Token 并返回剩余次数。`-1` 表示 Token 未注册或已失效。
  Future<Result<int>> checkLeft() async {
    Result<int>? lastError;
    for (final String host in _hosts) {
      try {
        int left = await _readLeft(host);
        if (left == -1) {
          // 脚本的逻辑：-1 说明 Token 存在但从未登录/已失效，先注册再查。
          await _register(host);
          left = await _readLeft(host);
        }
        _host = host;
        return Ok<int>(left);
      } on DioException catch (e) {
        lastError = Err<int>('network', _netMessage(e));
      } on FormatException {
        lastError = const Err<int>('parse', '题库返回的内容无法解析');
      }
    }
    return lastError ?? const Err<int>('network', '连不上万卷题库');
  }

  Future<Result<BankAnswer>> query({
    required String question,
    required HomeworkQuestionType type,
    required List<String> options,
    required int answerNum,
    required String wid,
    required String cid,
    required String courseName,
  }) async {
    final Map<String, String> form = <String, String>{
      'tm': question,
      'type': '${type.code}',
      'wid': wid,
      // 九九助手对选择题传空串，只有填空题才传空位数量。
      'answernum': answerNum > 0 ? '$answerNum' : '',
      'cid': cid,
      'options': jsonEncode(options),
      'ai': '0',
      'coursename': courseName,
    };
    Result<BankAnswer>? lastError;
    for (final String host in _hosts) {
      try {
        final Response<String> resp = await _dio.post<String>(
          '${host}api/query',
          queryParameters: <String, dynamic>{
            'token': token,
            'version': _kClientVersion,
            'ran': '${DateTime.now().millisecondsSinceEpoch}',
          },
          data: form,
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            responseType: ResponseType.plain,
          ),
        );
        final Map<String, dynamic>? json = _decode(resp.data);
        if (json == null) {
          lastError = const Err<BankAnswer>('parse', '题库返回的内容无法解析');
          continue;
        }
        final int code = int.tryParse('${json['code']}') ?? 0;
        final String data = '${json['data'] ?? ''}'.trim();
        final int left = int.tryParse('${json['left']}') ?? -1;
        final String msg = '${json['msg'] ?? ''}'.trim();
        if (code == 1 && data.isNotEmpty) {
          _host = host;
          return Ok<BankAnswer>(BankAnswer(text: data, left: left, message: msg));
        }
        return Err<BankAnswer>('api', msg.isEmpty ? '题库没有返回答案' : msg);
      } on DioException catch (e) {
        lastError = Err<BankAnswer>('network', _netMessage(e));
      }
    }
    return lastError ?? const Err<BankAnswer>('network', '连不上万卷题库');
  }

  Future<int> _readLeft(String host) async {
    final Response<String> resp = await _dio.get<String>(
      '${host}api/checkLeft',
      queryParameters: <String, dynamic>{
        'token': token,
        'ran': '${DateTime.now().millisecondsSinceEpoch}',
      },
      options: Options(responseType: ResponseType.plain),
    );
    final Map<String, dynamic>? json = _decode(resp.data);
    if (json == null) throw const FormatException('left');
    final dynamic data = json['data'];
    if (data is int) return data;
    return int.tryParse('$data') ?? -1;
  }

  Future<void> _register(String host) async {
    try {
      await _dio.put<String>(
        '${host}api/register',
        data: <String, String>{
          'token': token,
          'md5': md5.convert(utf8.encode(token)).toString(),
        },
        options: Options(
          contentType: Headers.jsonContentType,
          responseType: ResponseType.plain,
        ),
      );
    } on DioException {
      // 注册失败时让后面的 checkLeft 决定结果，不在这里编造成功。
    }
  }

  static Map<String, dynamic>? _decode(String? body) {
    if (body == null || body.trim().isEmpty) return null;
    try {
      final dynamic decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String _netMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '题库请求超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return '连不上万卷题库，请检查网络或代理';
      default:
        return '题库请求失败（${e.response?.statusCode ?? e.message ?? '未知错误'}）';
    }
  }
}
