import 'package:flutter/material.dart';

import 'core/crypto.dart';

void main() => runApp(const AutoChaoxingApp());

class AutoChaoxingApp extends StatelessWidget {
  const AutoChaoxingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto-Chaoxing',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D6F),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<Widget> _pages = <Widget>[
    _CoursesPage(),
    _SelfCheckPage(),
    _SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auto-Chaoxing')),
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: '课程'),
          NavigationDestination(icon: Icon(Icons.science_outlined), label: '自检'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}

class _CoursesPage extends StatelessWidget {
  const _CoursesPage();

  @override
  Widget build(BuildContext context) {
    // M1 阶段接 ChaoxingApi.fetchCourses()，这里先给出空态而不是假数据。
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '尚未登录。\nM1 阶段：登录页 → 课程列表 → 章节树。',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// 自检页：把协议里最容易写错的两个算法用固定向量跑一遍。
/// 这两条向量与 Python 参考实现（core/chaoxing_core.py）完全一致。
class _SelfCheckPage extends StatelessWidget {
  const _SelfCheckPage();

  static const String _aesExpect = 'FiK1hSgSEgMeqWPSRhRB+A==';
  static const String _encExpect = 'f72245dce1271d7e6039a4f3110a0575';

  @override
  Widget build(BuildContext context) {
    final String aes = aesCbcBase64('123456');
    final String enc = progressEnc(
      classId: '123',
      uid: '456',
      jobId: '789',
      objectId: 'abc',
      playTime: 0,
      duration: 600,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _row('AES-CBC("123456")', aes, aes == _aesExpect),
        const SizedBox(height: 12),
        _row('progressEnc(0s/600s)', enc, enc == _encExpect),
        const SizedBox(height: 24),
        const Text(
          '两条向量都应为绿色。若为红色，说明签名或加密实现被改坏了 —— '
          '不要提交，先对齐 core/chaoxing_core.py 的输出。',
        ),
      ],
    );
  }

  Widget _row(String label, String value, bool ok) {
    return Card(
      child: ListTile(
        leading: Icon(ok ? Icons.check_circle : Icons.error, color: ok ? Colors.green : Colors.red),
        title: Text(label),
        subtitle: SelectableText(value),
        trailing: Text(ok ? 'PASS' : 'FAIL'),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const <Widget>[
        ListTile(title: Text('节流间隔'), subtitle: Text('每题 2–4s 随机 · 每段进度 1s · 每课程 30s 起')),
        ListTile(title: Text('单账号串行'), subtitle: Text('同一时间只跑一个任务，避免并发风控')),
        ListTile(title: Text('考试功能'), subtitle: Text('仅提醒，不自动交卷')),
      ],
    );
  }
}
