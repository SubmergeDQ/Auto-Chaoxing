// Windows 自动覆盖更新的纯逻辑：生成「等待主进程退出 → 覆盖 → 重启」的脚本。
//
// 为什么必须是外部脚本：运行中的 exe / dll 不能被当前进程覆盖。
// 应用只能把压缩包解到临时目录、写好脚本、退出，剩下的交给脚本在进程结束后做。
//
// 单独放在 core 是为了能对路径转义做纯 Dart 测试——这里错一个引号，
// 更新就会在用户机器上静默失败，甚至把安装目录写坏。
// 目录可写检测涉及文件系统，放在 platform/update_installer.dart。

/// 生成应用更新的 PowerShell 脚本。
///
/// 步骤有意保持最小：备份主 exe → 覆盖整个目录 → 启动新版本。
/// 不做「先删旧文件」：覆盖失败时旧文件还在，损坏面比清空目录小。
String buildWindowsApplyScript({
  required int pid,
  required String stagingDir,
  required String appDir,
  required String exeName,
}) {
  String quote(String value) => "'${value.replaceAll("'", "''")}'";

  final String staging = quote(stagingDir);
  final String target = quote(appDir);
  final String exe = quote(exeName);
  return '''
\$ErrorActionPreference = 'Stop'
# 等旧进程退出：文件句柄释放有延迟，直接复制会报占用。
Wait-Process -Id $pid -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 600
\$target = $target
\$exe = Join-Path \$target $exe
# 只备份主程序：整个目录备份会占用双倍磁盘，而主程序坏了就无法再启动。
if (Test-Path \$exe) { Copy-Item \$exe "\$exe.bak" -Force }
Copy-Item -Path (Join-Path $staging '*') -Destination \$target -Recurse -Force
Start-Process -FilePath \$exe -WorkingDirectory \$target
''';
}
