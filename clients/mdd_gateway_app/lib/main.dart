import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/host/macos_host_service.dart';
import 'core/state/gateway_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    try {
      await MacHostService().ensureRunning();
    } on Object {
      // Auth/System surfaces retry with actionable errors. Startup remains available.
    }
  }
  final state = GatewayState();
  await state.initialize();
  runApp(MddGatewayApp(state: state));
}
