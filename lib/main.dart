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
  runApp(AutoChaoxingApp(
    api: ChaoxingApi(cookieJar: session.jar),
    session: session,
  ));
}

class AutoChaoxingApp extends StatefulWidget {
  /// [state] 与 [fontFamily] 只给测试与视觉取证注入，正常运行都传 null。
  const AutoChaoxingApp({
    super.key,
    this.state,
    this.fontFamily,
    this.api,
    this.session,
  });

  final AppState? state;
  final String? fontFamily;

  /// 正常运行时由 main 注入：带落盘 CookieJar 的 API。
  final ChaoxingApi? api;

  /// 多账号会话存储；测试为 null（内存模式）。
  final SessionJar? session;

  @override
  State<AutoChaoxingApp> createState() => _AutoChaoxingAppState();
}

class _AutoChaoxingAppState extends State<AutoChaoxingApp> {
  late final AppState _state =
      widget.state ?? AppState(api: widget.api, session: widget.session);
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
