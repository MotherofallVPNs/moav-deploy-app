import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';

import '../support/fixtures.dart';

ServiceStatusReport _report(List<ServiceStatus> services) =>
    ServiceStatusReport(services: services, collectedAt: DateTime(2026));

ServiceFlags _flags(Map<String, String> values) =>
    ServiceFlags(values: values, collectedAt: DateTime(2026));

void main() {
  group('ServiceStatusReport.downCount', () {
    test('a finished certbot and a disabled gooserelay are not down', () {
      final r = _report(const [
        ServiceStatus(name: 'sing-box', state: ServiceState.running),
        ServiceStatus(name: 'certbot', state: ServiceState.exited),
        ServiceStatus(name: 'gooserelay', state: ServiceState.never),
      ]);
      expect(r.runningCount, 1);
      expect(r.downCount(_flags({'ENABLE_GOOSERELAY': 'false'})), 0);
      // Neither needs the flags: one is a one-shot, the other never ran.
      expect(r.downCount(), 0);
    });

    test('a disabled service that was stopped is not down', () {
      final r = _report(const [
        ServiceStatus(name: 'gooserelay', state: ServiceState.exited),
        ServiceStatus(name: 'telemt', state: ServiceState.stopped),
      ]);
      expect(
        r.downCount(_flags({'ENABLE_GOOSERELAY': 'false', 'ENABLE_TELEMT': 'false'})),
        0,
      );
      // The same rows count while the flags say enabled or are not loaded.
      expect(
        r.downCount(_flags({'ENABLE_GOOSERELAY': 'true', 'ENABLE_TELEMT': 'true'})),
        2,
      );
      expect(r.downCount(), 2);
    });

    test('exited, stopped and unknown services still count as down', () {
      final r = _report(const [
        ServiceStatus(name: 'sing-box', state: ServiceState.exited),
        ServiceStatus(name: 'wireguard', state: ServiceState.stopped),
        ServiceStatus(name: 'admin', state: ServiceState.unknown),
        ServiceStatus(name: 'grafana', state: ServiceState.unhealthy),
        ServiceStatus(name: 'certbot', state: ServiceState.exited),
      ]);
      expect(r.downCount(), 3);
      expect(r.downCount(_flags(const {})), 3);
    });

    test('only an exited one-shot is done', () {
      for (final name in ServiceStatus.oneShots) {
        expect(ServiceStatus(name: name, state: ServiceState.exited).isDone, isTrue);
      }
      // A one-shot that was created but never ran did not finish.
      const created = ServiceStatus(name: 'certbot', state: ServiceState.stopped);
      expect(created.isDone, isFalse);
      expect(created.isDown(), isTrue);
      const crashed = ServiceStatus(name: 'sing-box', state: ServiceState.exited);
      expect(crashed.isDone, isFalse);
      expect(crashed.isDown(), isTrue);
    });

    test('the 2.3.1 status document has nothing down', () {
      final r = MoavCli.parseStatusJson(jsonFixture('status.json'))!;
      expect(r.services.length - r.runningCount, 3);
      expect(r.downCount(), 0);
    });
  });
}
