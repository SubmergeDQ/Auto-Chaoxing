// 学习通协议所需的加密与签名。
// 纯 Dart 实现：Android 与 Windows 行为完全一致，且可以被 dart test 直接覆盖。
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// 学习通 fanyalogin 的固定 AES 密钥（同时作为 IV）。
/// 注意：这是平台侧写死的常量，不是本项目生成的密钥。
const String kLoginAesKey = 'm2oh6Vu^HWe4_AES';

/// 视频进度签名里的固定盐。
const String kProgressSalt = r'd_yHJ!$pdA~5';

String md5Hex(String input) => md5.convert(utf8.encode(input)).toString();

/// 登录用的 uname/password 加密：AES-128-CBC + PKCS7 + Base64。
String aesCbcBase64(String plainText) {
  final Uint8List key = Uint8List.fromList(utf8.encode(kLoginAesKey));
  final Uint8List iv = Uint8List.fromList(utf8.encode(kLoginAesKey));
  final CBCBlockCipher engine = CBCBlockCipher(AESEngine());
  final PaddedBlockCipherImpl cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    engine,
  )..init(
      true,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );
  final Uint8List out = cipher.process(Uint8List.fromList(utf8.encode(plainText)));
  return base64.encode(out);
}

/// 视频进度签名。
///
/// enc = md5("[classId][uid][jobid][objectid][playTime*1000][盐][duration*1000][0_duration]")
///
/// playTime 与 duration 单位都是秒。字段顺序与方括号是协议的一部分，改动会导致进度被拒。
String progressEnc({
  required String classId,
  required String uid,
  required String jobId,
  required String objectId,
  required int playTime,
  required int duration,
}) {
  final String raw = '[$classId][$uid][$jobId][$objectId][${playTime * 1000}]'
      '[$kProgressSalt][${duration * 1000}][0_$duration]';
  return md5Hex(raw);
}
