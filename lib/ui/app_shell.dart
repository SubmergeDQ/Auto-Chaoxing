// 自适应外壳：宽屏用固定侧栏 + 单行顶栏，窄屏用底栏导航。
// 导航按范围分层：三个 Tab 是同一账号下的同级视图，课程内部的章节下钻由页面自己负责。
import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'about_page.dart';
import 'aux_pages.dart';
import 'courses_page.dart';
import 'run_console.dart';
import 'theme.dart';
import 'widgets.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.state});

  final AppState state;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// 设置里的二级页。非空时主区域显示它，顶栏换成带返回的标题。
  /// 不用 Navigator 压栈：宽屏侧栏要保持可见，压栈会把侧栏一起盖掉。
  SettingsSubPage? _sub;

  static const List<String> _titles = <String>['课程工作台', '任务执行', '设置'];
  static const List<String> _subtitles = <String>[
    '课程、章节与任务点',
    '执行进度与实时日志',
    '账号、诊断与运行约束',
  ];

  @override
  void initState() {
    super.initState();
    // 上一轮登录的 cookie 已经落盘，开机就在后台验一次；
    // 放首帧之后，避免把「恢复会话」的网络等待塞进开屏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.state.bootstrap());
    });
  }

  void _select(int index) {
    if (_index == index && _sub == null) return;
    setState(() {
      _index = index;
      _sub = null;
    });
  }

  void _openSub(SettingsSubPage page) => setState(() => _sub = page);

  void _closeSub() => setState(() => _sub = null);

  Widget _body() {
    final SettingsSubPage? sub = _sub;
    if (sub != null) {
      return switch (sub) {
        SettingsSubPage.selfCheck => SelfCheckPage(probe: widget.state.probe),
        SettingsSubPage.constraints => const ConstraintsPage(),
        SettingsSubPage.privacy => PrivacyPage(state: widget.state),
        SettingsSubPage.about => AboutPage(update: widget.state.update),
      };
    }
    switch (_index) {
      case 0:
        return CoursesPage(state: widget.state, onOpenRun: () => _select(1));
      case 1:
        return RunPage(state: widget.state, onGoToCourses: () => _select(0));
      default:
        return SettingsPage(
          state: widget.state,
          onOpen: _openSub,
          update: widget.state.update,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 1000;
    return PopScope(
      // 二级页时拦下系统返回，先回到设置列表而不是直接退出应用。
      canPop: _sub == null,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && _sub != null) _closeSub();
      },
      child: AnimatedBuilder(
        animation: widget.state,
        builder: (BuildContext context, Widget? _) {
          final bool running = widget.state.run.busy;
          final SettingsSubPage? sub = _sub;
          final List<Widget> actions = <Widget>[
            // 全局运行信号：切到设置页时也知道后台还在跑；已在执行页就不重复一遍。
            if (wide && running && _index != 1)
              const Padding(
                padding: EdgeInsets.only(right: AcxSpacing.sm),
                child: AcxStatusBadge(label: '运行中', status: AcxStatus.running),
              ),
            AcxAccountChip(
              name: widget.state.profile?.name ?? '',
              signedIn: widget.state.signedIn,
            ),
          ];
          final ({String title, String subtitle}) heading =
              sub == null ? (title: _titles[_index], subtitle: _subtitles[_index]) : describeSubPage(sub);
          final AcxTopBar topBar = AcxTopBar(
            title: heading.title,
            subtitle: heading.subtitle,
            actions: actions,
            leading: sub == null
                ? null
                : IconButton(
                    onPressed: _closeSub,
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    color: AcxColors.textSecondary,
                    tooltip: '返回设置',
                  ),
          );
          final Widget body = _body();

          if (wide) {
            return Scaffold(
              body: Row(
                children: <Widget>[
                  _Sidebar(index: _index, onSelect: _select, state: widget.state),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        topBar,
                        Expanded(child: body),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return Scaffold(
            appBar: topBar,
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              backgroundColor: AcxColors.surface,
              indicatorColor: AcxColors.brandSoft,
              destinations: <NavigationDestination>[
                const NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book_rounded),
                  label: '课程',
                ),
                NavigationDestination(
                  // 窄屏没有顶栏徽章的位置，用底栏小圆点提示后台仍在执行。
                  icon: _runIcon(const Icon(Icons.bolt_outlined), running),
                  selectedIcon: _runIcon(const Icon(Icons.bolt_rounded), running),
                  label: '执行',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: '设置',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _runIcon(Icon icon, bool running) {
    if (!running) return icon;
    return Badge(
      smallSize: 8,
      backgroundColor: AcxColors.brand,
      child: icon,
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.onSelect,
    required this.state,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      color: AcxColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AcxSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AcxSpacing.xl),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AcxColors.brand,
                    borderRadius: BorderRadius.circular(AcxRadius.sm),
                  ),
                  child: const Icon(Icons.auto_stories_rounded, size: 19, color: Colors.white),
                ),
                const SizedBox(width: AcxSpacing.md),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Auto-Chaoxing',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AcxColors.onSidebar,
                        ),
                      ),
                      Text(
                        '课程自动化客户端',
                        style: TextStyle(fontSize: 11, color: AcxColors.onSidebarMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AcxSpacing.xxl),
          _NavItem(
            icon: Icons.menu_book_outlined,
            label: '课程工作台',
            selected: index == 0,
            onTap: () => onSelect(0),
          ),
          _NavItem(
            icon: Icons.bolt_outlined,
            label: '任务执行',
            selected: index == 1,
            onTap: () => onSelect(1),
            showRunningDot: state.run.busy,
          ),
          _NavItem(
            icon: Icons.settings_outlined,
            label: '设置',
            selected: index == 2,
            onTap: () => onSelect(2),
          ),
          const Spacer(),
          const Divider(color: Color(0xFF2C5A52), height: 1),
          Padding(
            padding: const EdgeInsets.all(AcxSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      state.signedIn ? Icons.circle : Icons.circle_outlined,
                      size: 9,
                      color: state.signedIn ? const Color(0xFF6FD3AE) : AcxColors.onSidebarMuted,
                    ),
                    const SizedBox(width: AcxSpacing.sm),
                    Text(
                      state.signedIn ? '已连接 · ${state.profile?.name ?? ''}' : '未连接账号',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AcxColors.onSidebar),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '协议 v0.1 · 全部请求在本地发出',
                  style: TextStyle(fontSize: 11, color: AcxColors.onSidebarMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showRunningDot = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showRunningDot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AcxSpacing.md, vertical: 2),
      child: Material(
        color: selected ? AcxColors.sidebarActive : Colors.transparent,
        borderRadius: BorderRadius.circular(AcxRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AcxRadius.sm),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AcxSpacing.md),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : AcxColors.onSidebarMuted,
                ),
                const SizedBox(width: AcxSpacing.md),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? Colors.white : AcxColors.onSidebarMuted,
                  ),
                ),
                if (showRunningDot) ...<Widget>[
                  const Spacer(),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6FD3AE),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
