import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main() => runApp(const AutoChaoxingApp());

class AutoChaoxingApp extends StatefulWidget {
  /// [state] 与 [fontFamily] 只给测试与视觉取证注入，正常运行都传 null。
  const AutoChaoxingApp({super.key, this.state, this.fontFamily});

  final AppState? state;
  final String? fontFamily;

  @override
  State<AutoChaoxingApp> createState() => _AutoChaoxingAppState();
}

class _AutoChaoxingAppState extends State<AutoChaoxingApp> {
  late final AppState _state = widget.state ?? AppState();
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
