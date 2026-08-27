import 'package:flutter_test/flutter_test.dart';
import 'package:mdd_gateway_app/core/host/macos_host_service.dart';

void main() {
  MacHostStatus status(String vm, {bool ready = false}) => MacHostStatus(
    vm: vm,
    gatewayReady: ready,
    gatewayUrl: 'https://127.0.0.1:8443',
  );

  test('gateway installation is reconciled for every recoverable VM state', () {
    expect(status('not_installed').requiresGatewayInstall, isTrue);
    expect(status('stopped').requiresGatewayInstall, isTrue);
    expect(status('running').requiresGatewayInstall, isTrue);
  });

  test('ready and broken states do not request gateway installation', () {
    expect(status('running', ready: true).requiresGatewayInstall, isFalse);
    expect(status('broken').requiresGatewayInstall, isFalse);
  });
}
