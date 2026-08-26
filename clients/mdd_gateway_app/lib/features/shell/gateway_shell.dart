import 'package:flutter/material.dart';

import '../../core/state/gateway_state.dart';
import '../pages/calls_page.dart';
import '../pages/devices_page.dart';
import '../pages/diagnostics_page.dart';
import '../pages/egress_page.dart';
import '../pages/esim_page.dart';
import '../pages/keepalive_page.dart';
import '../pages/messages_page.dart';
import '../pages/notifications_page.dart';
import '../pages/overview_page.dart';
import '../pages/system_page.dart';

class GatewayShell extends StatefulWidget {
  const GatewayShell({
    required this.state,
    required this.themeMode,
    required this.onThemeChanged,
    super.key,
  });

  final GatewayState state;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<GatewayShell> createState() => _GatewayShellState();
}

class _GatewayShellState extends State<GatewayShell> {
  int _selected = 0;

  static const destinations = <_Destination>[
    _Destination(
      '概览',
      '所有线路与宿主机状态',
      Icons.dashboard_outlined,
      Icons.dashboard_rounded,
    ),
    _Destination(
      '设备',
      '读卡器、模块和 SIM',
      Icons.developer_board_outlined,
      Icons.developer_board_rounded,
    ),
    _Destination('通话', '拨号、来电和语音留言', Icons.phone_outlined, Icons.phone_rounded),
    _Destination(
      '短信',
      '会话与短信发送',
      Icons.chat_bubble_outline_rounded,
      Icons.chat_bubble_rounded,
    ),
    _Destination(
      'eSIM',
      'Profile 与通知管理',
      Icons.sim_card_download_outlined,
      Icons.sim_card_download_rounded,
    ),
    _Destination(
      '余额与保号',
      '余额监测和定时任务',
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet_rounded,
    ),
    _Destination('网络出口', '国家路由和代理库', Icons.route_outlined, Icons.route_rounded),
    _Destination(
      '通知',
      'Webhook 与推送',
      Icons.notifications_outlined,
      Icons.notifications_rounded,
    ),
    _Destination(
      '系统',
      '设置、备份和更新',
      Icons.settings_outlined,
      Icons.settings_rounded,
    ),
    _Destination(
      '诊断',
      '告警、日志与支持包',
      Icons.monitor_heart_outlined,
      Icons.monitor_heart_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final expandedRail = width >= 1180;
    final rail = width >= 800;
    final page = <Widget>[
      OverviewPage(state: widget.state),
      DevicesPage(state: widget.state),
      CallsPage(state: widget.state),
      MessagesPage(state: widget.state),
      EsimPage(state: widget.state),
      KeepalivePage(state: widget.state),
      EgressPage(state: widget.state),
      NotificationsPage(state: widget.state),
      SystemPage(
        state: widget.state,
        themeMode: widget.themeMode,
        onThemeChanged: widget.onThemeChanged,
      ),
      DiagnosticsPage(state: widget.state),
    ][_selected];

    final content = _PageFrame(
      destination: destinations[_selected],
      refreshing: widget.state.refreshing,
      onRefresh: widget.state.refresh,
      child: page,
    );

    if (!rail) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'MDD Sim Gateway',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              onPressed: widget.state.refreshing ? null : widget.state.refresh,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新',
            ),
          ],
        ),
        drawer: NavigationDrawer(
          selectedIndex: _selected,
          onDestinationSelected: (index) {
            setState(() => _selected = index);
            Navigator.pop(context);
          },
          children: [
            const _DrawerHeader(),
            for (final destination in destinations)
              NavigationDrawerDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: Text(destination.title),
              ),
            const Divider(indent: 24, endIndent: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('退出登录'),
                onTap: widget.state.logout,
              ),
            ),
          ],
        ),
        body: content,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: expandedRail,
            selectedIndex: _selected,
            onDestinationSelected: (index) => setState(() => _selected = index),
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
              child: expandedRail ? const _WideBrand() : const _CompactBrand(),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: expandedRail
                      ? _RailFooter(state: widget.state)
                      : IconButton(
                          onPressed: widget.state.logout,
                          tooltip: '退出登录',
                          icon: const Icon(Icons.logout_rounded),
                        ),
                ),
              ),
            ),
            destinations: [
              for (final destination in destinations)
                NavigationRailDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: Text(destination.title),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.destination,
    required this.refreshing,
    required this.onRefresh,
    required this.child,
  });

  final _Destination destination;
  final bool refreshing;
  final VoidCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 19, 18, 15),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      destination.subtitle,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: refreshing ? null : onRefresh,
                tooltip: '刷新',
                icon: refreshing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _Destination {
  const _Destination(this.title, this.subtitle, this.icon, this.selectedIcon);

  final String title;
  final String subtitle;
  final IconData icon;
  final IconData selectedIcon;
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 24, 20, 20),
      child: _WideBrand(),
    );
  }
}

class _WideBrand extends StatelessWidget {
  const _WideBrand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CompactBrand(),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MDD Sim Gateway',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text('Native control', style: TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Icon(Icons.sim_card_rounded, color: Colors.white),
    );
  }
}

class _RailFooter extends StatelessWidget {
  const _RailFooter({required this.state});

  final GatewayState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 218,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.lan_rounded, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '局域网已连接',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        state.endpoint?.host ?? '—',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: state.logout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('退出登录'),
          ),
        ],
      ),
    );
  }
}
