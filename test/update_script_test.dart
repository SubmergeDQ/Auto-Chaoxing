import 'dart:io';

import 'package:auto_chaoxing/core/update/update_script.dart';
import 'package:auto_chaoxing/platform/update_installer.dart' show canWriteToDirectory;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Windows 覆盖更新脚本', () {
    test('等旧进程退出后覆盖并重启，路径含单引号也能转义', () {
      final String script = buildWindowsApplyScript(
        pid: 4321,
        stagingDir: r"C:\Temp\acx_update_1",
        appDir: r"D:\Apps\Auto'Chaoxing",
        exeName: 'auto_chaoxing.exe',
      );

      expect(script, contains('Wait-Process -Id 4321'));
      expect(script, contains('Copy-Item'));
      expect(script, contains('Start-Process'));
      // PowerShell 单引号字符串里，单引号要写成两个。
      expect(script, contains("D:\\Apps\\Auto''Chaoxing"));
      expect(script, contains('auto_chaoxing.exe'));
      // 覆盖前先备份主程序，失败时还能启动旧版本。
      expect(script, contains('.bak'));
    });

    test('目录可写检测：存在的目录为真，不存在的为假', () async {
      final Directory dir = await Directory.systemTemp.createTemp('acx_write_test');
      expect(await canWriteToDirectory(dir.path), isTrue);

      final String missing = '${dir.path}${Platform.pathSeparator}not_there';
      expect(await canWriteToDirectory(missing), isFalse);

      await dir.delete(recursive: true);
    });
  });
}
