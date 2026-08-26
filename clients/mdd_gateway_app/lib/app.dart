import 'package:flutter/material.dart';

import 'core/state/gateway_state.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_page.dart';
import 'features/shell/gateway_shell.dart';

class MddGatewayApp extends StatefulWidget {
  const MddGatewayApp({required this.state, super.key});

  final GatewayState state;

  @override
  State<MddGatewayApp> createState() => _MddGatewayAppState();
}

class _MddGatewayAppState extends State<MddGatewayApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => MaterialApp(
        title: 'MDD Sim Gateway',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeMode,
        home: !widget.state.initialized
            ? const _BootPage()
            : widget.state.authenticated
            ? GatewayShell(
                state: widget.state,
                themeMode: _themeMode,
                onThemeChanged: (mode) => setState(() => _themeMode = mode),
              )
            : AuthPage(state: widget.state),
      ),
    );
  }
}

class _BootPage extends StatelessWidget {
  const _BootPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GatewayMark(size: 64),
            SizedBox(height: 28),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _GatewayMark extends StatelessWidget {
  const _GatewayMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Icon(
        Icons.sim_card_rounded,
        size: size * .52,
        color: Colors.white,
      ),
    );
  }
}
