import 'package:flutter/material.dart';

import 'core/chaoxing_api.dart';
import 'platform/session_store.dart';
import 'state/app_state.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  // 会话要落盘，起 App 前先把存储准备好（读一个目录，毫秒级）。
  WidgetsFlutterBinding.ensureInitialized();
  final SessionJar session = await SessionJar.open();
  runApp(AutoChaoxingApp(api: ChaoxingApi(cookieJar: session.jar), purgeSession: session.purge));
}

class AutoChaoxingApp extends StatefulWidget {
  /// [state] 与 [fontFamily] 只给测试与视觉取证注入，正常运行都传 null。
  const AutoChaoxingApp({super.key, this.state, this.fontFamily, this.api, this.purgeSession});

  final AppState? state;
  final String? fontFamily;

  /// 正常运行时由 main 注入：带落盘 CookieJar 的 API。
  final ChaoxingApi? api;

  /// 断开连接时清盘。
  final Future<void> Function()? purgeSession;

  @override
  State<AutoChaoxingApp> createState() => _AutoChaoxingAppState();
}

class _AutoChaoxingAppState extends State<AutoChaoxingApp> {
  late final AppState _state =
      widget.state ?? AppState(api: widget.api, purgeSession: widget.purgeSession);
  late final bool _ownsState = widget.state == null;

  @override
  void dispose() {
    if (_ownsState) _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto-Chaoxing',
      debugShowCheckedModeBanner: false,
      theme: buildAcxTheme(fontFamily: widget.fontFamily),
      home: AppShell(state: _state),
    );
  }
}
