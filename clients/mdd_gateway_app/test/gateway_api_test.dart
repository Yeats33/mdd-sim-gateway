import 'package:flutter_test/flutter_test.dart';
import 'package:mdd_gateway_app/core/api/gateway_api.dart';

void main() {
  group('GatewayApi endpoint policy', () {
    test('accepts HTTPS and loopback development HTTP', () {
      expect(
        () => GatewayApi(baseUri: Uri.parse('https://gateway.local:8443')),
        returnsNormally,
      );
      expect(
        () => GatewayApi(baseUri: Uri.parse('http://127.0.0.1:8443')),
        returnsNormally,
      );
    });

    test('rejects cleartext LAN endpoints', () {
      expect(
        () => GatewayApi(baseUri: Uri.parse('http://192.168.1.20:8443')),
        throwsA(isA<GatewayApiException>()),
      );
    });

    test('formats certificate fingerprints for human comparison', () {
      expect(GatewayApi.displayFingerprint('0011aabb'), '00:11:AA:BB');
    });
  });
}
