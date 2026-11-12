// 自适应外壳：宽屏用固定侧栏 + 单行顶栏，窄屏用底栏导航。
// 导航按范围分层：三个 Tab 是同一账号下的同级视图，课程内部的章节下钻由页面自己负责。
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'aux_pages.dart';
import 'courses_page.dart';
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

  static const List<String> _titles = <String>['课程工作台', '协议自检', '设置'];
  static const List<String> _subtitles = <String>[
    '课程、章节与任务点',
    '两个本地算法的正确性检查',
    '运行方式与隐私保护',
  ];

  void _select(int index) {
    if (_index == index) return;
    setState(() => _index = index);
  }

  Widget _body() {
    switch (_index) {
      case 0:
        return CoursesPage(state: widget.state);
      case 1:
        return const SelfCheckPage();
      default:
        return SettingsPage(state: widget.state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 1000;
    return AnimatedBuilder(
      animation: widget.state,
      builder: (BuildContext context, Widget? _) {
        final List<Widget> actions = <Widget>[
          AcxAccountChip(
            name: widget.state.profile?.name ?? '',
            signedIn: widget.state.signedIn,
          ),
        ];
        final AcxTopBar topBar = AcxTopBar(
          title: _titles[_index],
          subtitle: _subtitles[_index],
          actions: actions,
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
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book_rounded),
                label: '课程',
              ),
              NavigationDestination(
                icon: Icon(Icons.science_outlined),
                selectedIcon: Icon(Icons.science_rounded),
                label: '自检',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: '设置',
              ),
            ],
          ),
        );
      },
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
            icon: Icons.science_outlined,
            label: '协议自检',
            selected: index == 1,
            onTap: () => onSelect(1),
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
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
