import 'package:flutter/material.dart';

import 'app.dart';
import 'core/state/gateway_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = GatewayState();
  await state.initialize();
  runApp(MddGatewayApp(state: state));
}
