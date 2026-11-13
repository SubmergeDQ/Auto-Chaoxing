// 签到协议里的纯规则：预签到 HTML 判定、提交回执判定、活动时间解析。
//
// 单独放 core 是为了能用固定样本做纯 Dart 测试：这些判定错一个字，
// 用户看到的就是「签到失败」而不是「其实可以签」，必须锁死。
import 'models.dart';

/// 预签到 HTML 的判定。可签时返回 null，继续走提交。
///
/// 只认中文关键词：HTML 里也有 `validate` 这类脚本变量，按英文判会误报。
SignAttempt? judgePreSign(String html) {
  if (html.contains('已经签到') || html.contains('已签到')) {
    return const SignAttempt(SignOutcome.alreadySigned, message: '这节课已经签过了');
  }
  if (html.contains('人脸')) {
    return const SignAttempt(SignOutcome.needFace, message: '这次签到需要人脸识别，请在手机上完成');
  }
  if (html.contains('验证码')) {
    return const SignAttempt(SignOutcome.needValidate, message: '这次签到需要验证码，请在手机上完成');
  }
  if (html.contains('已结束') || html.contains('已截止')) {
    return const SignAttempt(SignOutcome.expired, message: '签到已经结束');
  }
  return null;
}

/// 提交回执的判定。平台回的是纯文本，成功时就是 `success`。
SignAttempt judgeSignResponse(String body) {
  final String text = body.trim();
  final String lower = text.toLowerCase();
  final String raw = text.length > 80 ? '${text.substring(0, 80)}…' : text;

  if (lower.contains('success2')) {
    return const SignAttempt(SignOutcome.expired, message: '签到已结束（平台回了 success2）');
  }
  if (lower.contains('success')) {
    return const SignAttempt(SignOutcome.success, message: '签到成功');
  }
  if (text.contains('已经签到') || text.contains('已签到')) {
    return const SignAttempt(SignOutcome.alreadySigned, message: '这节课已经签过了');
  }
  if (lower.contains('validate')) {
    return const SignAttempt(SignOutcome.needValidate, message: '需要验证码，请在手机上完成');
  }
  if (text.contains('人脸')) {
    return const SignAttempt(SignOutcome.needFace, message: '需要人脸识别，请在手机上完成');
  }
  if (text.contains('距离') || text.contains('位置') || text.contains('定位')) {
    return const SignAttempt(SignOutcome.needLocation, message: '这次签到要求定位，请在手机上完成');
  }
  if (text.contains('未开始')) {
    return const SignAttempt(SignOutcome.notStarted, message: '签到还没开始');
  }
  if (text.contains('已结束') || text.contains('截止')) {
    return const SignAttempt(SignOutcome.expired, message: '签到已经结束');
  }
  return SignAttempt(
    SignOutcome.error,
    message: raw.isEmpty ? '签到失败，平台没有返回原因' : '签到失败：$raw',
  );
}

/// 活动时间可能是秒 / 毫秒时间戳，也可能是 `yyyy-MM-dd HH:mm:ss`。
/// 解析不了就返回 null，界面按「时间未知」处理，而不是猜一个可用窗口。
///
/// 学习通的时间字段格式基本一致，作业也复用这套解析。
DateTime? parseChaoxingTime(dynamic value) {
  if (value == null) return null;
  if (value is num) return _fromEpoch(value.toInt());
  final String s = '$value'.trim();
  if (s.isEmpty) return null;
  final int? n = int.tryParse(s);
  if (n != null) return _fromEpoch(n);
  return DateTime.tryParse(s.replaceFirst(' ', 'T'));
}

DateTime? _fromEpoch(int n) {
  if (n <= 0) return null;
  // 10 位是秒，13 位是毫秒；用 1e11 作分界（2153 年之前的毫秒都大于它）。
  final int ms = n < 100000000000 ? n * 1000 : n;
  return DateTime.fromMillisecondsSinceEpoch(ms);
}
